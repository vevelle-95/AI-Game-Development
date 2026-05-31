extends Node
class_name AI_Controller

# =============================================================================
# IS-MCTS  (Information-Set Monte Carlo Tree Search)
# Game of the Generals — Generals & Trapo Variant
# =============================================================================

# ── Tunable parameters ────────────────────────────────────────────────────────
const NUM_DETERMINISATIONS : int   = 20
const MCTS_ITERATIONS      : int   = 150
const MAX_ROLLOUT_DEPTH    : int   = 12
const UCB_C                : float = 1.414
const GAMMA                : float = 0.95
const TIME_LIMIT_SEC       : float = 5.0

# ── Reward constants ──────────────────────────────────────────────────────────
const R_WIN_FLAG   : float =  1000.0
const R_WIN_UNIT   : float =    10.0
const R_LOSE_UNIT  : float =    -8.0
const R_TIE        : float =    -1.0
const R_ADVANCE    : float =     0.4
const R_BRIBE_BASE : float =     6.0

# ── Unit pool (mirrors Bayesian.UNIT_POOL_COUNTS) ─────────────────────────────
const UNIT_POOL_COUNTS : Dictionary = {
	GameConstants.Rank.FLAG:       1,
	GameConstants.Rank.GENERAL_5:  1,
	GameConstants.Rank.GENERAL_4:  1,
	GameConstants.Rank.GENERAL_3:  1,
	GameConstants.Rank.COLONEL:    1,
	GameConstants.Rank.MAJOR:      1,
	GameConstants.Rank.LIEUTENANT: 1,
	GameConstants.Rank.SERGEANT:   1,
	GameConstants.Rank.SPY:        2,
	GameConstants.Rank.TRAPO:      1,
	GameConstants.Rank.PRIVATE:    7,
}

# =============================================================================
# NODE POOL  — each node is a Dictionary stored in _nodes: Array
# Keys: "parent"(int), "action"(Dictionary), "children"(Array),
#       "visits"(int), "total_reward"(float),
#       "untried_actions"(Array), "is_terminal"(bool), "is_ai_turn"(bool)
# All field reads are cast explicitly to avoid Variant inference errors.
# =============================================================================

var _nodes: Array = []

func _node_new(parent_idx: int, action: Dictionary, is_ai: bool) -> int:
	var n: Dictionary = {
		"parent":          parent_idx,
		"action":          action,
		"children":        [],
		"visits":          0,
		"total_reward":    0.0,
		"untried_actions": [],
		"is_terminal":     false,
		"is_ai_turn":      is_ai
	}
	_nodes.append(n)
	return _nodes.size() - 1


func _node_ucb1(idx: int, parent_visits: int) -> float:
	var n: Dictionary = _nodes[idx]
	var v: int = int(n["visits"])
	if v == 0:
		return 1e18
	var tr: float = float(n["total_reward"])
	return (tr / float(v)) + UCB_C * sqrt(log(float(parent_visits)) / float(v))


func _node_best_child(idx: int) -> int:
	var n: Dictionary = _nodes[idx]
	var best_idx: int   = -1
	var best_val: float = -1e18
	var nv: int = int(n["visits"])
	for ch_idx in n["children"]:
		var v: float = _node_ucb1(int(ch_idx), nv)
		if v > best_val:
			best_val = v
			best_idx = int(ch_idx)
	return best_idx


# ── Injected references ───────────────────────────────────────────────────────
var _bayesian:      Bayesian
var _arbiter:       Arbiter
var _unit_behavior: UnitBehavior
var _board_rows:    int
var _board_cols:    int

# ── Aggregation table ─────────────────────────────────────────────────────────
var _action_table: Dictionary = {}


# =============================================================================
# PUBLIC API
# =============================================================================

func initialise(
		bayesian:      Bayesian,
		arbiter:       Arbiter,
		unit_behavior: UnitBehavior,
		board_rows:    int,
		board_cols:    int
) -> void:
	_bayesian      = bayesian
	_arbiter       = arbiter
	_unit_behavior = unit_behavior
	_board_rows    = board_rows
	_board_cols    = board_cols


func choose_move(
		unit_map:  Dictionary,
		rows:      int,
		cols:      int,
		ai_wallet: int
) -> Dictionary:
	_board_rows = rows
	_board_cols = cols
	_action_table.clear()

	var start_ms: int = Time.get_ticks_msec()

	for _d in range(NUM_DETERMINISATIONS):
		var elapsed: float = float(Time.get_ticks_msec() - start_ms) / 1000.0
		if elapsed >= TIME_LIMIT_SEC:
			break
		var world: Dictionary = _sample_world(unit_map)
		_run_mcts(world, rows, cols, ai_wallet)

	var best_key:   String = ""
	var best_score: float  = -1e18

	for key in _action_table.keys():
		var e: Dictionary = _action_table[key]
		var score: float  = float(e["reward"]) / float(maxi(int(e["visits"]), 1))
		if score > best_score:
			best_score = score
			best_key   = str(key)

	if best_key != "":
		var chosen: Dictionary = _action_table[best_key]
		print("IS-MCTS: chose '%s' %s->%s  (score=%.2f, visits=%d)" % [
			str(chosen["action"]),
			str(chosen["src"]),
			str(chosen["dst"]),
			best_score,
			int(chosen["visits"])
		])
		return {
			"action": chosen["action"],
			"src":    chosen["src"],
			"dst":    chosen["dst"]
		}

	print("IS-MCTS: no valid tree action, falling back to Bayesian greedy.")
	return _bayesian.choose_move(unit_map, rows, cols, ai_wallet)


# =============================================================================
# STAGE 1 — DETERMINISATION
# =============================================================================

func _sample_world(unit_map: Dictionary) -> Dictionary:
	var world:        Dictionary = {}
	var unknown_uids: Array      = []
	var uid_to_dist:  Dictionary = {}

	for pos in unit_map.keys():
		var entry: Dictionary = unit_map[pos].duplicate()

		if _get_owner(entry) == GameConstants.Team.AI:
			world[pos] = entry
			continue

		var uid: int = int(entry["uid"])

		if _bayesian.confirmed.has(uid):
			entry["sampled_rank"] = _bayesian.confirmed[uid]
			world[pos] = entry
		else:
			unknown_uids.append(uid)
			uid_to_dist[uid] = _bayesian.rank_distribution(uid)
			entry["sampled_rank"] = GameConstants.Rank.PRIVATE
			world[pos] = entry

	# Residual pool: total minus confirmed
	var residual: Dictionary = {}
	for r in UNIT_POOL_COUNTS.keys():
		residual[r] = int(UNIT_POOL_COUNTS[r])

	for pos2 in world.keys():
		var e: Dictionary = world[pos2]
		if _get_owner(e) != GameConstants.Team.AI and _bayesian.confirmed.has(int(e["uid"])):
			var sr: GameConstants.Rank = e["sampled_rank"] as GameConstants.Rank
			residual[sr] = maxi(0, int(residual.get(sr, 0)) - 1)

	# Sample unknown UIDs jointly
	unknown_uids.shuffle()
	for uid2 in unknown_uids:
		var dist: Dictionary        = uid_to_dist[uid2]
		var sampled: GameConstants.Rank = _sample_from_dist(dist, residual)
		residual[sampled] = maxi(0, int(residual.get(sampled, 0)) - 1)
		for pos3 in world.keys():
			var e2: Dictionary = world[pos3]
			if e2.has("uid") and int(e2["uid"]) == int(uid2):
				e2["sampled_rank"] = sampled
				world[pos3] = e2
				break

	return world


func _sample_from_dist(dist: Dictionary, residual: Dictionary) -> GameConstants.Rank:
	var filtered: Dictionary = {}
	var total:    float      = 0.0

	for r in dist.keys():
		var p: float = float(dist[r])
		if p <= 0.0:
			continue
		if int(residual.get(r, 0)) <= 0:
			continue
		filtered[r] = p
		total += p

	if total <= 0.0:
		for r2 in residual.keys():
			if int(residual[r2]) > 0:
				filtered[r2] = 1.0
				total += 1.0

	if total <= 0.0:
		return GameConstants.Rank.PRIVATE

	var roll:       float = randf() * total
	var cumulative: float = 0.0
	for r3 in filtered.keys():
		cumulative += float(filtered[r3])
		if roll <= cumulative:
			return r3 as GameConstants.Rank

	return filtered.keys().back() as GameConstants.Rank


# =============================================================================
# STAGE 2 — MCTS
# =============================================================================

func _run_mcts(world: Dictionary, rows: int, cols: int, ai_wallet: int) -> void:
	_nodes.clear()
	var root_idx: int = _node_new(
		-1,
		{"action": "root", "src": Vector2i(-1, -1), "dst": Vector2i(-1, -1)},
		true
	)
	var root_node: Dictionary = _nodes[root_idx]
	root_node["untried_actions"] = _get_legal_actions(world, true, rows, cols, ai_wallet)

	for _i in range(MCTS_ITERATIONS):
		var node_idx:  int        = root_idx
		var sim_world: Dictionary = _clone_world(world)
		var sim_wallet: int       = ai_wallet

		# ── Selection ────────────────────────────────────────────────────────
		var sel_node: Dictionary = _nodes[node_idx]
		while (sel_node["untried_actions"] as Array).is_empty() \
				and not (sel_node["children"] as Array).is_empty() \
				and not bool(sel_node["is_terminal"]):
			node_idx  = _node_best_child(node_idx)
			sel_node  = _nodes[node_idx]
			var sel_action: Dictionary = sel_node["action"]
			_apply_action(sim_world, sel_action, sim_wallet)
			if str(sel_action["action"]) == "bribe":
				sim_wallet = maxi(0, sim_wallet - _get_bribe_cost(sel_action, sim_world))

		# ── Expansion ────────────────────────────────────────────────────────
		var exp_node: Dictionary = _nodes[node_idx]
		var exp_untried: Array   = exp_node["untried_actions"]
		if not exp_untried.is_empty() and not bool(exp_node["is_terminal"]):
			var action_idx: int        = randi() % int(exp_untried.size())
			var action:     Dictionary = exp_untried[action_idx]
			exp_untried.remove_at(action_idx)

			var child_world:  Dictionary = _clone_world(sim_world)
			var child_wallet: int        = sim_wallet
			_apply_action(child_world, action, child_wallet)
			if str(action["action"]) == "bribe":
				child_wallet = maxi(0, child_wallet - _get_bribe_cost(action, child_world))

			var child_is_ai: bool = not bool(exp_node["is_ai_turn"])
			var child_idx:   int  = _node_new(node_idx, action, child_is_ai)

			var child_node: Dictionary = _nodes[child_idx]
			child_node["untried_actions"] = _get_legal_actions(
				child_world, child_is_ai, rows, cols, child_wallet
			)
			child_node["is_terminal"] = _is_terminal(child_world)
			(exp_node["children"] as Array).append(child_idx)

			node_idx   = child_idx
			sim_world  = child_world
			sim_wallet = child_wallet

		# ── Rollout ───────────────────────────────────────────────────────────
		var reward: float = _rollout(sim_world, sim_wallet, rows, cols, 0)

		# ── Backpropagation ───────────────────────────────────────────────────
		var back_idx: int = node_idx
		while back_idx >= 0:
			var bn: Dictionary = _nodes[back_idx]
			bn["visits"] = int(bn["visits"]) + 1
			var sign: float = 1.0 if bool(bn["is_ai_turn"]) else -1.0
			bn["total_reward"] = float(bn["total_reward"]) + sign * reward
			back_idx = int(bn["parent"])

	# ── Aggregate root children into _action_table ────────────────────────────
	var final_root: Dictionary = _nodes[root_idx]
	for ch_idx in (final_root["children"] as Array):
		var ch: Dictionary    = _nodes[int(ch_idx)]
		var ch_action: Dictionary = ch["action"]
		var key: String       = _action_key(ch_action)
		if not _action_table.has(key):
			_action_table[key] = {
				"action": ch_action["action"],
				"src":    ch_action["src"],
				"dst":    ch_action["dst"],
				"visits": 0,
				"reward": 0.0
			}
		var tbl: Dictionary = _action_table[key]
		tbl["visits"] = int(tbl["visits"]) + int(ch["visits"])
		tbl["reward"] = float(tbl["reward"]) + float(ch["total_reward"])


# =============================================================================
# ROLLOUT & EVALUATION
# =============================================================================

func _rollout(
		world:  Dictionary,
		wallet: int,
		rows:   int,
		cols:   int,
		depth:  int
) -> float:
	if depth >= MAX_ROLLOUT_DEPTH or _is_terminal(world):
		return _evaluate(world, rows)

	var is_ai_ply: bool  = (depth % 2 == 0)
	var actions:   Array = _get_legal_actions(world, is_ai_ply, rows, cols, wallet)

	if actions.is_empty():
		return _evaluate(world, rows)

	var action:     Dictionary = _rollout_policy(actions, world)
	var new_world:  Dictionary = _clone_world(world)
	var new_wallet: int        = wallet
	_apply_action(new_world, action, new_wallet)
	if str(action["action"]) == "bribe":
		new_wallet = maxi(0, new_wallet - _get_bribe_cost(action, world))

	return GAMMA * _rollout(new_world, new_wallet, rows, cols, depth + 1)


func _evaluate(world: Dictionary, rows: int) -> float:
	var score: float = 0.0
	for pos in world.keys():
		var entry = world[pos]
		if not (entry is Dictionary):
			continue
		var is_ai: bool            = _get_owner(entry) == GameConstants.Team.AI
		var rank:  GameConstants.Rank = _get_rank(entry)
		var sign:  float           = 1.0 if is_ai else -1.0

		if rank == GameConstants.Rank.FLAG:
			score += sign * 100.0
			continue

		var py: int = int((pos as Vector2i).y)
		if is_ai:
			score += sign * float(py) * R_ADVANCE
		else:
			score += sign * float(rows - 1 - py) * R_ADVANCE

		score += sign * float(int(rank)) * 0.5

	return score


func _rollout_policy(actions: Array, world: Dictionary) -> Dictionary:
	var combat: Array = []
	var other:  Array = []
	for a in actions:
		var ad: Dictionary = a
		if str(ad["action"]) == "move" and world.has(ad["dst"]):
			combat.append(ad)
		else:
			other.append(ad)
	if not combat.is_empty() and randf() < 0.6:
		return combat[randi() % int(combat.size())]
	if not other.is_empty():
		return other[randi() % int(other.size())]
	return actions[randi() % int(actions.size())]


# =============================================================================
# LEGAL ACTIONS
# =============================================================================

func _get_legal_actions(
		world:   Dictionary,
		is_ai:   bool,
		rows:    int,
		cols:    int,
		wallet:  int
) -> Array:
	var actions:    Array              = []
	var team:       GameConstants.Team = GameConstants.Team.AI if is_ai else GameConstants.Team.PLAYER
	var enemy_team: GameConstants.Team = GameConstants.Team.PLAYER if is_ai else GameConstants.Team.AI

	for pos in world.keys():
		var entry = world[pos]
		if not (entry is Dictionary):
			continue
		if _get_owner(entry) != team:
			continue

		var rank: GameConstants.Rank = _get_rank(entry)
		if rank == GameConstants.Rank.FLAG:
			continue

		for dst in _get_adjacent(pos as Vector2i, rows, cols):
			if world.has(dst):
				if _get_owner(world[dst]) == team:
					continue
			actions.append({"action": "move", "src": pos, "dst": dst})

		if rank == GameConstants.Rank.TRAPO:
			for epos in world.keys():
				var eentry = world[epos]
				if not (eentry is Dictionary):
					continue
				if _get_owner(eentry) != enemy_team:
					continue
				var erank: GameConstants.Rank = _get_rank(eentry)
				if erank == GameConstants.Rank.FLAG:
					continue
				if not _unit_behavior.can_corrupt(pos as Vector2i, epos as Vector2i, erank):
					continue
				var cost: int = _unit_behavior.get_corrupt_cost(erank)
				if wallet >= cost:
					actions.append({"action": "bribe", "src": pos, "dst": epos})

	return actions


# =============================================================================
# WORLD MUTATION
# =============================================================================

func _apply_action(world: Dictionary, action: Dictionary, _wallet: int) -> void:
	var atype: String = str(action["action"])
	match atype:
		"move":
			_apply_move(world, action["src"] as Vector2i, action["dst"] as Vector2i)
		"bribe":
			_apply_bribe(world, action["dst"] as Vector2i)


func _apply_move(world: Dictionary, src: Vector2i, dst: Vector2i) -> void:
	if not world.has(src):
		return
	var attacker: Dictionary      = world[src]
	var attacker_rank: GameConstants.Rank = _get_rank(attacker)

	if world.has(dst):
		var defender:      Dictionary      = world[dst]
		var defender_rank: GameConstants.Rank = _get_rank(defender)
		var result: Arbiter.CombatResult   = _arbiter.resolve_combat(attacker_rank, defender_rank)
		match result:
			Arbiter.CombatResult.ATTACKER_WINS, \
			Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS:
				world.erase(src)
				world[dst] = attacker
			Arbiter.CombatResult.DEFENDER_WINS, \
			Arbiter.CombatResult.GAME_OVER_DEFENDER_WINS:
				world.erase(src)
			Arbiter.CombatResult.TIE:
				world.erase(src)
				world.erase(dst)
	else:
		world.erase(src)
		world[dst] = attacker


func _apply_bribe(world: Dictionary, target_pos: Vector2i) -> void:
	world.erase(target_pos)


func _is_terminal(world: Dictionary) -> bool:
	var ai_flag:     bool = false
	var player_flag: bool = false
	for pos in world.keys():
		var e = world[pos]
		if not (e is Dictionary):
			continue
		var r: GameConstants.Rank = _get_rank(e)
		if r == GameConstants.Rank.FLAG:
			if _get_owner(e) == GameConstants.Team.AI:
				ai_flag = true
			else:
				player_flag = true
	return not ai_flag or not player_flag


func _get_bribe_cost(action: Dictionary, world: Dictionary) -> int:
	var dst: Vector2i = action["dst"] as Vector2i
	if not world.has(dst):
		return 0
	return _unit_behavior.get_corrupt_cost(_get_rank(world[dst]))


# =============================================================================
# UTILITY HELPERS
# =============================================================================

func _clone_world(world: Dictionary) -> Dictionary:
	var clone: Dictionary = {}
	for pos in world.keys():
		var e = world[pos]
		clone[pos] = (e as Dictionary).duplicate() if e is Dictionary else e
	return clone


func _get_rank(entry: Dictionary) -> GameConstants.Rank:
	if entry.has("sampled_rank"):
		return entry["sampled_rank"] as GameConstants.Rank
	if entry.has("type"):
		return _unit_type_to_rank_local(entry["type"])
	return GameConstants.Rank.PRIVATE


func _unit_type_to_rank_local(unit_type: Variant) -> GameConstants.Rank:
	match int(unit_type):
		0:  return GameConstants.Rank.FLAG
		1:  return GameConstants.Rank.GENERAL_5
		2:  return GameConstants.Rank.GENERAL_4
		3:  return GameConstants.Rank.GENERAL_3
		4:  return GameConstants.Rank.COLONEL
		5:  return GameConstants.Rank.MAJOR
		6:  return GameConstants.Rank.LIEUTENANT
		7:  return GameConstants.Rank.SERGEANT
		8:  return GameConstants.Rank.SPY
		9:  return GameConstants.Rank.TRAPO
		10: return GameConstants.Rank.PRIVATE
	return GameConstants.Rank.PRIVATE


func _get_owner(entry: Dictionary) -> GameConstants.Team:
	if entry.has("owner"):
		return entry["owner"] as GameConstants.Team
	return GameConstants.Team.PLAYER


func _get_adjacent(pos: Vector2i, rows: int, cols: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
	]
	for off in offsets:
		var np: Vector2i = pos + off
		if np.x >= 0 and np.x < cols and np.y >= 0 and np.y < rows:
			result.append(np)
	return result


func _action_key(action: Dictionary) -> String:
	var src: Vector2i = action["src"] as Vector2i
	var dst: Vector2i = action["dst"] as Vector2i
	return "%s|%d,%d|%d,%d" % [str(action["action"]), src.x, src.y, dst.x, dst.y]


# =============================================================================
# DEBUG
# =============================================================================

func debug_action_table() -> String:
	var lines: Array[String] = ["=== IS-MCTS Action Table ==="]
	var sorted_keys: Array = _action_table.keys()
	sorted_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(_action_table[a]["visits"]) > int(_action_table[b]["visits"])
	)
	for key in sorted_keys:
		var e: Dictionary = _action_table[key]
		var avg: float    = float(e["reward"]) / float(maxi(int(e["visits"]), 1))
		lines.append("  [%s] %s->%s  visits=%d  avg=%.3f" % [
			str(e["action"]), str(e["src"]), str(e["dst"]),
			int(e["visits"]), avg
		])
	return "\n".join(lines)
