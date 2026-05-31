extends Node
class_name Bayesian

# =============================================================================
# BAYESIAN NETWORK AI — Game of the Generals (Generals & Trapo Variant)
# =============================================================================
#
# OVERVIEW
# --------
# This AI maintains a probabilistic belief state over every hidden player unit,
# then uses that belief state to score candidate moves via a Bayesian decision
# framework.  The network has three conceptual layers:
#
#   [EVIDENCE LAYER]  — Observable signals gathered from the board each turn
#         |
#         v
#   [BELIEF LAYER]    — Per-unit rank probability distributions (prior → posterior)
#         |
#         v
#   [DECISION LAYER]  — Move scoring using expected utility (EU) over rank beliefs
#
# EVIDENCE SIGNALS (update beliefs each turn)
# -------------------------------------------
#   E1 – combat_outcome  : win / loss / tie after a fight reveals relative rank
#   E2 – vision_range    : tile count a unit can see encodes its rank bracket
#   E3 – diagonal_vision : only Generals have diagonal line-of-sight
#   E4 – position_history: row proximity to flag correlates with flag / high-value units
#   E5 – aggression      : units that attack first tend to be higher-ranked
#   E6 – avoidance       : units that flee are likely lower-ranked
#   E7 – bribe_target    : player Trapo bribing a unit reveals its exact rank
#   E8 – turn_inactivity : units never moved are more likely to be the Flag
#
# CONDITIONAL PROBABILITY TABLES (CPT)
# -------------------------------------
# Each evidence signal E_i updates the rank distribution P(rank | E_i) via Bayes:
#
#   P(rank | E_i) ∝ P(E_i | rank) × P(rank)
#
# Exact rank is revealed (probability → 1.0) upon:
#   • A combat win/loss where one unit is definitively stronger/weaker
#   • A bribe reveal
#   • Being spotted with diagonal vision (confirms General)
#
# DECISION SCORING (Expected Utility)
# ------------------------------------
# For each AI unit and each candidate destination tile:
#
#   score(src → dst) = Σ_r [ P(player_unit_at_dst = r) × utility(ai_rank, r) ]
#
#   utility(ai_rank, r) =
#     +WIN_VALUE   if ai_rank defeats r (per Arbiter rules)
#     +FLAG_VALUE  if r == FLAG (game-over bonus)
#     –LOSS_RISK   if r defeats ai_rank
#     +POSITIONAL  proximity-to-enemy-flag bonus
#     –EXPOSURE    risk penalty for moving high-value units into danger
#     +TRAPO_BONUS if bribe action is profitable
#
# SPECIAL UNIT STRATEGIES
# ------------------------
#   SPY      → aggressively hunts tiles with high P(GENERAL) probability
#   FLAG     → never moves; always scores 0
#   TRAPO    → evaluates bribe actions alongside movement; picks the higher EU
#   PRIVATE  → seeks tiles with high P(SPY) since Private always beats Spy
#
# =============================================================================

const WIN_VALUE    := 10.0
const FLAG_VALUE   := 1000.0
const LOSS_RISK    := -8.0
const TIE_VALUE    := -1.0
const POSITIONAL   := 0.5
const EXPOSURE_PEN := -3.0
const BRIBE_BONUS  := 5.0

# Probability thresholds
const CERTAIN      := 0.95
const LIKELY       := 0.65
const POSSIBLE     := 0.35

# All non-Flag, non-Trapo ranks in ascending order
const ALL_RANKS := [
	GameConstants.Rank.SPY,
	GameConstants.Rank.PRIVATE,
	GameConstants.Rank.SERGEANT,
	GameConstants.Rank.LIEUTENANT,
	GameConstants.Rank.MAJOR,
	GameConstants.Rank.COLONEL,
	GameConstants.Rank.GENERAL_3,
	GameConstants.Rank.GENERAL_4,
	GameConstants.Rank.GENERAL_5,
	GameConstants.Rank.FLAG,
	GameConstants.Rank.TRAPO,
]

# Unit counts in the game (player starts with these)
const UNIT_POOL_COUNTS := {
	GameConstants.Rank.FLAG:      1,
	GameConstants.Rank.GENERAL_5: 1,
	GameConstants.Rank.GENERAL_4: 1,
	GameConstants.Rank.GENERAL_3: 1,
	GameConstants.Rank.COLONEL:   1,
	GameConstants.Rank.MAJOR:     1,
	GameConstants.Rank.LIEUTENANT:1,
	GameConstants.Rank.SERGEANT:  1,
	GameConstants.Rank.SPY:       2,
	GameConstants.Rank.TRAPO:     1,
	GameConstants.Rank.PRIVATE:   7,
}

# ── Data structures ──────────────────────────────────────────────────────────

# beliefs[uid] → { rank: float }  (probability distribution over ranks)
var beliefs: Dictionary = {}

# confirmed[uid] → GameConstants.Rank  (certain if revealed)
var confirmed: Dictionary = {}

# Tracks how many of each player rank have been eliminated (for pool accounting)
var eliminated_pool: Dictionary = {}

# Tracks each player unit's movement history: uid → Array[Vector2i]
var move_history: Dictionary = {}

# Tracks which player units have ever attacked: uid → bool
var has_attacked: Dictionary = {}

# Tracks turn count since last move for each uid
var turns_idle: Dictionary = {}

# Reference to board & helpers (injected on initialise)
var _board: Node
var _arbiter: Arbiter
var _unit_behavior: UnitBehavior

# =============================================================================
# PUBLIC API
# =============================================================================

## Call once after the board is ready.
func initialise(board: Node, arbiter: Arbiter, unit_behavior: UnitBehavior) -> void:
	_board = board
	_arbiter = arbiter
	_unit_behavior = unit_behavior
	_reset_eliminated_pool()

## Call at the start of every AI turn to increment idle counters.
func tick_idle() -> void:
	for uid in turns_idle.keys():
		turns_idle[uid] += 1

## Registers a new player unit that entered the AI's awareness.
func register_player_unit(uid: int) -> void:
	if beliefs.has(uid):
		return
	beliefs[uid] = _build_uniform_prior()
	move_history[uid] = []
	has_attacked[uid] = false
	turns_idle[uid] = 0

## Returns the most-likely rank for a player unit (MAP estimate).
func map_rank(uid: int) -> GameConstants.Rank:
	if confirmed.has(uid):
		return confirmed[uid]
	if not beliefs.has(uid):
		return GameConstants.Rank.PRIVATE  # safe default
	return _argmax(beliefs[uid])

## Returns the full rank probability distribution for a unit.
func rank_distribution(uid: int) -> Dictionary:
	if confirmed.has(uid):
		var d: Dictionary = {}
		for r in ALL_RANKS:
			d[r] = 0.0
		d[confirmed[uid]] = 1.0
		return d
	if beliefs.has(uid):
		return beliefs[uid].duplicate()
	return _build_uniform_prior()

# =============================================================================
# EVIDENCE UPDATES  (call these whenever the relevant event occurs)
# =============================================================================

## E1 – Combat outcome.
## attacker_uid / defender_uid: one must be the AI unit, the other the player unit.
## is_ai_attacker: true if the AI unit was the attacker.
func update_from_combat(
	ai_rank: GameConstants.Rank,
	player_uid: int,
	result: Arbiter.CombatResult,
	is_ai_attacker: bool
) -> void:
	register_player_unit(player_uid)
	has_attacked[player_uid] = not is_ai_attacker  # player attacked if AI was defender

	# ── Exact reveal cases ──
	match result:
		Arbiter.CombatResult.ATTACKER_WINS:
			if is_ai_attacker:
				# AI won → player unit's rank was lower than ai_rank (or was SPY beaten by PRIVATE)
				_narrow_below(player_uid, ai_rank)
			else:
				# Player attacked and won → player rank > ai_rank (or Spy exception)
				_narrow_above(player_uid, ai_rank)

		Arbiter.CombatResult.DEFENDER_WINS:
			if is_ai_attacker:
				# AI attacked, player defended and won → player rank > ai_rank
				_narrow_above(player_uid, ai_rank)
			else:
				# Player attacked, AI won defending → player rank < ai_rank
				_narrow_below(player_uid, ai_rank)

		Arbiter.CombatResult.TIE:
			# Same rank — exactly confirms the rank
			_pin_rank(player_uid, ai_rank)

		Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS, \
		Arbiter.CombatResult.GAME_OVER_DEFENDER_WINS:
			# Flag revealed
			if is_ai_attacker:
				_pin_rank(player_uid, GameConstants.Rank.FLAG)
			else:
				_pin_rank(player_uid, GameConstants.Rank.FLAG)

	_normalise(player_uid)
	_accounting_pass()

## E2+E3 – Vision evidence.
## Call each turn for each visible player unit based on how far it can see.
func update_from_vision(player_uid: int, observed_range: int, has_diag: bool) -> void:
	register_player_unit(player_uid)
	if has_diag:
		# Only Generals have diagonal vision
		_keep_only(player_uid, [
			GameConstants.Rank.GENERAL_3,
			GameConstants.Rank.GENERAL_4,
			GameConstants.Rank.GENERAL_5,
		])
		return

	# P(vision_range=v | rank) — likelihood table
	var likelihood: Dictionary = {}
	for r in ALL_RANKS:
		var v = GameConstants.get_vision_range(r)
		likelihood[r] = 1.0 if v == observed_range else 0.05
	_apply_likelihood(player_uid, likelihood)
	_normalise(player_uid)

## E4 – Position heuristic.
## Units that stay near the back (top rows for player, high y for player side)
## are more likely to be the Flag or high-value units.
func update_from_position(player_uid: int, pos: Vector2i, board_rows: int) -> void:
	register_player_unit(player_uid)
	var depth: float = float(pos.y) / float(board_rows - 1)  # 0=top, 1=bottom
	# Player units are in the bottom half (y >= 6 on 10-row board)
	# "depth" close to 1.0 → very back of player's formation
	# Flag probability increases the further back a unit is
	var flag_boost: float = max(0.0, depth - 0.5) * 2.0   # 0..1

	if beliefs.has(player_uid):
		var dist = beliefs[player_uid]
		dist[GameConstants.Rank.FLAG] = clamp(
			dist.get(GameConstants.Rank.FLAG, 0.1) * (1.0 + flag_boost),
			0.0, 1.0
		)
		_normalise(player_uid)

## E5 – Aggression evidence.
## Player unit moved toward AI territory — slight upward rank pressure.
func update_from_aggression(player_uid: int) -> void:
	register_player_unit(player_uid)
	has_attacked[player_uid] = true
	# Aggressive movers are unlikely to be the Flag
	if beliefs.has(player_uid):
		beliefs[player_uid][GameConstants.Rank.FLAG] *= 0.1
		_normalise(player_uid)

## E6 – Avoidance evidence.
## Player unit retreated — more likely to be a lower-ranked unit or Flag.
func update_from_avoidance(player_uid: int) -> void:
	register_player_unit(player_uid)
	if beliefs.has(player_uid):
		var dist = beliefs[player_uid]
		# Boost low ranks
		for r in [GameConstants.Rank.PRIVATE, GameConstants.Rank.SERGEANT,
				  GameConstants.Rank.FLAG, GameConstants.Rank.SPY]:
			dist[r] = dist.get(r, 0.0) * 2.0
		_normalise(player_uid)

## E7 – Bribe / revealed rank (exact).
func update_from_bribe_reveal(player_uid: int, revealed_rank: GameConstants.Rank) -> void:
	_pin_rank(player_uid, revealed_rank)

## E8 – Idle unit.
## Units that never move are more likely to be the Flag.
func update_from_idle(player_uid: int, idle_turns: int) -> void:
	register_player_unit(player_uid)
	if beliefs.has(player_uid) and idle_turns >= 3:
		beliefs[player_uid][GameConstants.Rank.FLAG] = \
			beliefs[player_uid].get(GameConstants.Rank.FLAG, 0.1) * float(idle_turns)
		_normalise(player_uid)

# =============================================================================
# DECISION ENGINE — choose the best AI move
# =============================================================================

## Returns the best (src, dst) move pair for the AI, or (Vector2i(-1,-1), …) if none.
## unit_map: the full board unit_map from board.gd
## Returns: { "src": Vector2i, "dst": Vector2i, "score": float,
##            "action": String }   action = "move" | "bribe" | "skip"
func choose_move(unit_map: Dictionary, board_rows: int, board_cols: int,
				 ai_wallet: int) -> Dictionary:

	var best_score := -INF
	var best_move := { "src": Vector2i(-1,-1), "dst": Vector2i(-1,-1),
					   "score": -INF, "action": "skip" }

	# Collect all AI units
	var ai_units: Array = []
	for pos in unit_map.keys():
		var entry = unit_map[pos]
		if _get_owner(entry) == GameConstants.Team.AI:
			ai_units.append({ "pos": pos, "entry": entry })

	# Collect all player units (for context)
	var player_units: Array = []
	for pos in unit_map.keys():
		var entry = unit_map[pos]
		if _get_owner(entry) != GameConstants.Team.AI:
			player_units.append({ "pos": pos, "entry": entry })
			# Update idle counters
			var uid = entry.uid
			turns_idle[uid] = turns_idle.get(uid, 0)
			if not move_history.has(uid) or move_history[uid].is_empty():
				update_from_idle(uid, turns_idle.get(uid, 0))

	# Refresh position beliefs
	for pu in player_units:
		update_from_position(pu.entry.uid, pu.pos, board_rows)

	# Score every possible AI move
	for au in ai_units:
		var src: Vector2i = au.pos
		var entry = au.entry
		var ai_rank: GameConstants.Rank = _board.unit_type_to_rank(entry.type)

		# Flag never moves
		if ai_rank == GameConstants.Rank.FLAG:
			continue

		var neighbors = _get_adjacent(src, board_rows, board_cols)

		for dst in neighbors:
			if unit_map.has(dst):
				var target = unit_map[dst]
				if _get_owner(target) == GameConstants.Team.AI:
					continue  # no friendly fire

				var player_uid = target.uid
				register_player_unit(player_uid)
				var score = _score_combat_move(ai_rank, player_uid, src, dst, board_rows)
				if score > best_score:
					best_score = score
					best_move = { "src": src, "dst": dst, "score": score, "action": "move" }
			else:
				var score = _score_positional_move(ai_rank, src, dst, board_rows, board_cols, unit_map)
				if score > best_score:
					best_score = score
					best_move = { "src": src, "dst": dst, "score": score, "action": "move" }

		# TRAPO bribe evaluation
		if ai_rank == GameConstants.Rank.TRAPO:
			var bribe_result = _evaluate_bribe(src, player_units, ai_wallet, board_rows)
			if bribe_result.score > best_score:
				best_score = bribe_result.score
				best_move = bribe_result

	return best_move

# =============================================================================
# SCORING HELPERS
# =============================================================================

## Score a move that results in combat at dst (occupied by a player unit).
func _score_combat_move(
	ai_rank: GameConstants.Rank,
	player_uid: int,
	src: Vector2i,
	dst: Vector2i,
	board_rows: int
) -> float:
	var dist = rank_distribution(player_uid)
	var eu := 0.0

	for r in dist.keys():
		var p: float = dist[r]
		if p <= 0.0:
			continue
		var player_rank: GameConstants.Rank = r as GameConstants.Rank
		var result = _arbiter.resolve_combat(ai_rank, player_rank)
		match result:
			Arbiter.CombatResult.ATTACKER_WINS:
				var val = WIN_VALUE
				if player_rank == GameConstants.Rank.FLAG:
					val = FLAG_VALUE
				eu += p * val
			Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS:
				eu += p * FLAG_VALUE
			Arbiter.CombatResult.DEFENDER_WINS, Arbiter.CombatResult.GAME_OVER_DEFENDER_WINS:
				eu += p * LOSS_RISK
			Arbiter.CombatResult.TIE:
				eu += p * TIE_VALUE

	# Penalty: exposing high-value AI units unnecessarily
	if _unit_behavior.is_high_value(ai_rank):
		eu += EXPOSURE_PEN * _enemy_threat_density(dst)

	return eu

## Score a move to an empty tile based on strategy.
func _score_positional_move(
	ai_rank: GameConstants.Rank,
	src: Vector2i,
	dst: Vector2i,
	board_rows: int,
	board_cols: int,
	unit_map: Dictionary
) -> float:
	var score := 0.0

	# Advance toward player half (higher y = player territory on 10-row board)
	var advance: float = float(dst.y - src.y) * POSITIONAL
	score += advance

	# SPY strategy: move toward tiles with high P(GENERAL)
	if ai_rank == GameConstants.Rank.SPY:
		score += _proximity_to_high_prob_rank(dst, [
			GameConstants.Rank.GENERAL_3,
			GameConstants.Rank.GENERAL_4,
			GameConstants.Rank.GENERAL_5
		]) * 2.0

	# PRIVATE strategy: move toward tiles with high P(SPY)
	if ai_rank == GameConstants.Rank.PRIVATE:
		score += _proximity_to_high_prob_rank(dst, [GameConstants.Rank.SPY]) * 1.5

	# Generals: cautious advance, avoid frontlines alone
	if _unit_behavior.is_general(ai_rank):
		score += EXPOSURE_PEN * _enemy_threat_density(dst) * 0.5

	# Penalty for exposing the top of board (flag cluster defense)
	if dst.y < 2:
		score -= 2.0

	# Centre-file bonus (columns 3-7 on a 10-col board) for flexible positioning
	if dst.x >= 3 and dst.x <= board_cols - 4:
		score += 0.3

	return score

## Evaluate whether TRAPO should bribe a player unit.
func _evaluate_bribe(
	trapo_pos: Vector2i,
	player_units: Array,
	ai_wallet: int,
	board_rows: int
) -> Dictionary:
	var best_score := -INF
	var best_target := Vector2i(-1, -1)

	for pu in player_units:
		var target_pos: Vector2i = pu.pos
		var uid = pu.entry.uid
		var dist = float(trapo_pos.distance_to(target_pos))

		if dist > UnitBehavior.CORRUPT_RANGE:
			continue

		# BUG FIX: The original code used _board.unit_type_to_rank(pu.entry.type) which
		# reads the player's true rank directly from unit_map — a hard fog-of-war violation.
		# The AI's Trapo was effectively omniscient when choosing bribe targets.
		# We now use map_rank(uid): the Bayesian MAP estimate (confirmed rank if known,
		# otherwise the argmax of the belief distribution). This mirrors how every other
		# part of the decision engine handles player units.
		register_player_unit(uid)
		var estimated_rank: GameConstants.Rank = map_rank(uid)

		# Skip if the AI believes this unit is the Flag (cannot bribe Flag).
		if estimated_rank == GameConstants.Rank.FLAG:
			continue

		# Range / legality check uses the estimated rank.
		if not _unit_behavior.can_corrupt(trapo_pos, target_pos, estimated_rank):
			continue

		# Wallet check: use the estimated bribe cost so the AI doesn't overspend.
		var estimated_cost: int = _unit_behavior.get_corrupt_cost(estimated_rank)
		if ai_wallet < estimated_cost:
			continue

		# Compute expected utility by integrating over the full belief distribution,
		# consistent with how _score_combat_move works elsewhere in this class.
		var eu := 0.0
		var belief_dist: Dictionary = rank_distribution(uid)
		for r in belief_dist.keys():
			var p: float = belief_dist[r]
			if p <= 0.0:
				continue
			var r_rank: GameConstants.Rank = r as GameConstants.Rank
			if r_rank == GameConstants.Rank.FLAG:
				continue  # Flag is never bribable; skip its probability mass
			var rv: float = float(r_rank as int)
			var bc: int   = _unit_behavior.get_corrupt_cost(r_rank)
			# Only count this rank if the wallet would actually cover it.
			if ai_wallet >= bc:
				eu += p * (rv * BRIBE_BONUS - float(bc) * 0.02)

		# Extra value if the unit is confirmed high-value through legitimate evidence.
		if confirmed.has(uid) and _unit_behavior.is_high_value(confirmed[uid]):
			eu += WIN_VALUE

		if eu > best_score:
			best_score = eu
			best_target = target_pos

	if best_target == Vector2i(-1, -1):
		return { "src": trapo_pos, "dst": Vector2i(-1,-1), "score": -INF, "action": "skip" }

	return { "src": trapo_pos, "dst": best_target, "score": best_score, "action": "bribe" }

# =============================================================================
# BELIEF MANAGEMENT INTERNALS
# =============================================================================

func _build_uniform_prior() -> Dictionary:
	# Prior respects the known unit pool composition
	var total := 0
	for r in UNIT_POOL_COUNTS.keys():
		total += UNIT_POOL_COUNTS[r]
	var prior: Dictionary = {}
	for r in UNIT_POOL_COUNTS.keys():
		prior[r] = float(UNIT_POOL_COUNTS[r]) / float(total)
	return prior

func _apply_likelihood(uid: int, likelihood: Dictionary) -> void:
	if not beliefs.has(uid):
		return
	var dist = beliefs[uid]
	for r in dist.keys():
		dist[r] *= likelihood.get(r, 1.0)

func _normalise(uid: int) -> void:
	if not beliefs.has(uid):
		return
	var dist = beliefs[uid]
	var total := 0.0
	for r in dist.keys():
		total += dist[r]
	if total <= 0.0:
		# Reset to uniform if degenerate
		beliefs[uid] = _build_uniform_prior()
		return
	for r in dist.keys():
		dist[r] /= total

func _pin_rank(uid: int, rank: GameConstants.Rank) -> void:
	confirmed[uid] = rank
	var d: Dictionary = {}
	for r in ALL_RANKS:
		d[r] = 0.0
	d[rank] = 1.0
	beliefs[uid] = d

## Restrict belief to ranks strictly below ai_rank (attacker won).
func _narrow_below(uid: int, ai_rank: GameConstants.Rank) -> void:
	if not beliefs.has(uid):
		register_player_unit(uid)
	var dist = beliefs[uid]
	for r in dist.keys():
		var rr: GameConstants.Rank = r as GameConstants.Rank
		# Special case: Private beats Spy even though Spy rank int > Private
		if ai_rank == GameConstants.Rank.PRIVATE and rr == GameConstants.Rank.SPY:
			dist[r] = 1.0  # This must be the Spy
			continue
		# Trapo always loses — if AI won, defender is not Trapo (unless same)
		if rr == GameConstants.Rank.TRAPO and ai_rank != GameConstants.Rank.TRAPO:
			dist[r] = 0.0
			continue
		if (rr as int) >= (ai_rank as int):
			dist[r] = 0.0
	_normalise(uid)

## Restrict belief to ranks strictly above ai_rank (player won).
func _narrow_above(uid: int, ai_rank: GameConstants.Rank) -> void:
	if not beliefs.has(uid):
		register_player_unit(uid)
	var dist = beliefs[uid]
	for r in dist.keys():
		var rr: GameConstants.Rank = r as GameConstants.Rank
		# Special case: Spy vs Private — Private wins, so if player unit is attacking
		# and beats AI's Spy, it must be a Private
		if ai_rank == GameConstants.Rank.SPY and rr == GameConstants.Rank.PRIVATE:
			continue  # allow Private
		if (rr as int) <= (ai_rank as int):
			dist[r] = 0.0
	_normalise(uid)

## Keep only the specified ranks.
func _keep_only(uid: int, ranks: Array) -> void:
	if not beliefs.has(uid):
		register_player_unit(uid)
	var dist = beliefs[uid]
	for r in dist.keys():
		if not (r in ranks):
			dist[r] = 0.0
	_normalise(uid)

## Accounting pass: if all units of a rank are confirmed, zero it out in remaining beliefs.
func _accounting_pass() -> void:
	# Count confirmed ranks
	var confirmed_counts: Dictionary = {}
	for uid in confirmed.keys():
		var r = confirmed[uid]
		confirmed_counts[r] = confirmed_counts.get(r, 0) + 1

	# For ranks where confirmed count == pool count, set belief to 0 for unconfirmed units
	for r in confirmed_counts.keys():
		var pool_count = UNIT_POOL_COUNTS.get(r, 0)
		if confirmed_counts[r] >= pool_count:
			# All units of this rank are accounted for; zero it in all unconfirmed beliefs
			for uid in beliefs.keys():
				if not confirmed.has(uid):
					beliefs[uid][r] = 0.0
					# Don't normalise here; caller should call _normalise afterwards
			# Normalise all affected
			for uid in beliefs.keys():
				if not confirmed.has(uid):
					_normalise(uid)

func _reset_eliminated_pool() -> void:
	for r in UNIT_POOL_COUNTS.keys():
		eliminated_pool[r] = 0

func _argmax(dist: Dictionary) -> GameConstants.Rank:
	var best_rank = GameConstants.Rank.PRIVATE
	var best_prob := -1.0
	for r in dist.keys():
		if dist[r] > best_prob:
			best_prob = dist[r]
			best_rank = r as GameConstants.Rank
	return best_rank

# =============================================================================
# SPATIAL HELPERS
# =============================================================================

func _get_adjacent(pos: Vector2i, rows: int, cols: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for off in offsets:
		var np = pos + off
		if np.x >= 0 and np.x < cols and np.y >= 0 and np.y < rows:
			result.append(np)
	return result

## Returns a 0..1 density of how many nearby player units threaten dst.
func _enemy_threat_density(dst: Vector2i) -> float:
	# Lightweight proxy: count number of confirmed high-rank player units within 2 tiles
	var count := 0
	for uid in confirmed.keys():
		var r: GameConstants.Rank = confirmed[uid]
		if _unit_behavior.is_high_value(r):
			count += 1
	return clamp(float(count) / 5.0, 0.0, 1.0)

## Returns a score for proximity (in belief space) to certain rank targets.
func _proximity_to_high_prob_rank(dst: Vector2i, target_ranks: Array) -> float:
	var score := 0.0
	for uid in beliefs.keys():
		if not move_history.has(uid) or move_history[uid].is_empty():
			continue
		var last_pos: Vector2i = move_history[uid].back()
		var dist: float = float(dst.distance_to(last_pos))
		if dist > 3.0:
			continue
		var proba := 0.0
		for tr in target_ranks:
			proba += beliefs[uid].get(tr, 0.0)
		score += proba * (1.0 / max(dist, 0.5))
	return score

func _get_owner(entry) -> GameConstants.Team:
	if typeof(entry) == TYPE_DICTIONARY and entry.has("owner"):
		return entry.owner
	return GameConstants.Team.PLAYER

# =============================================================================
# DIAGNOSTIC / DEBUG
# =============================================================================

## Returns a human-readable belief summary string for the given unit.
func debug_beliefs(player_uid: int) -> String:
	if not beliefs.has(player_uid):
		return "UID %d: not registered" % player_uid
	var dist = beliefs[player_uid]
	var lines: Array[String] = ["UID %d belief distribution:" % player_uid]
	# Sort by probability descending
	var pairs: Array = []
	for r in dist.keys():
		pairs.append([r, dist[r]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	for pair in pairs:
		if pair[1] > 0.001:
			lines.append("  %-20s %.3f" % [
				_unit_behavior.get_rank_name(pair[0] as GameConstants.Rank),
				pair[1]
			])
	if confirmed.has(player_uid):
		lines.append("  *** CONFIRMED: %s ***" % _unit_behavior.get_rank_name(confirmed[player_uid]))
	return "\n".join(lines)

## Dump entire belief state for debugging.
func debug_all_beliefs() -> String:
	var out: Array[String] = ["=== BayesianAI Belief State ==="]
	for uid in beliefs.keys():
		out.append(debug_beliefs(uid))
	return "\n".join(out)
