extends Control

signal log_message(message: String)
signal selected_tile_unit_info(unit_name: String, rank: String, vision: String, movement: String)
signal phase_changed(phase_name: String)
signal turn_changed(turn_name: String)
signal bounty_changed(total_bounty: int, last_bounty: int, killed_unit_name: String)

@onready var game_manager: GameManager = GameManager.new()
@onready var unit_behavior: UnitBehavior = UnitBehavior.new()
@onready var arbiter: Arbiter = Arbiter.new()
@onready var bayesian: Bayesian = Bayesian.new()
@onready var ai_controller: AI_Controller = AI_Controller.new()

@export var tile_scene: PackedScene
@export var columns := 10
@export var rows := 10

@onready var grid = $"CenterContainer/Grid"

var unit_map := {} # Vector2i -> {"type": UnitType, "uid": int}


enum UnitType {
	FLAG,
	FIVE_STAR,
	FOUR_STAR,
	THREE_STAR,
	COLONEL,
	MAJOR,
	LIEUTENANT,
	SERGEANT,
	SPY,
	TRAPO,
	PRIVATE
}

var selected_tile := Vector2i(-1, -1)
var tile_map := {}
var placed_counts := {}
var setup_locked := false
var next_unit_uid := 1
var moved_uids := []
var revealed_enemy_tiles := {}
var revealed_rank_only := {}
var armed_unit_pos := Vector2i(-1, -1)
var pickup_entry = null
var pickup_src_pos := Vector2i(-1, -1)
var turn_number := 1
var bribe_mode := false
var has_moved_this_turn := false  # ONE MOVE PER TURN: tracks if the player has already moved a piece this turn
var ai_turn_pending := false      # Set true when it becomes the AI's turn; processed in _process()


# BRIBE SYSTEM: uid -> { "moves_remaining": int, "original_owner": GameConstants.Team }
# While a unit is in this dict, it is temporarily controlled by the bribing team.
# Each move it makes decrements moves_remaining. When it hits 0, ownership reverts.
const BRIBE_MOVE_DURATION := 3
var bribed_units := {}


# TEMP: what unit you are placing
var selected_unit := UnitType.FIVE_STAR

const UNIT_ORDER: Array[String] = [
	"FLAG",
	"FIVE_STAR",
	"FOUR_STAR",
	"THREE_STAR",
	"COLONEL",
	"MAJOR",
	"LIEUTENANT",
	"SERGEANT",
	"SPY",
	"TRAPO",
	"PRIVATE"
]

const DEPLOYMENT_ROWS := 4

const UNIT_LIMITS := {
	UnitType.FLAG: 1,
	UnitType.FIVE_STAR: 1,
	UnitType.FOUR_STAR: 1,
	UnitType.THREE_STAR: 1,
	UnitType.COLONEL: 1,
	UnitType.MAJOR: 1,
	UnitType.LIEUTENANT: 1,
	UnitType.SERGEANT: 1,
	UnitType.SPY: 2,
	UnitType.TRAPO: 1,
	UnitType.PRIVATE: 7
}

const UNIT_RANK_NAMES := {
	UnitType.FLAG: "Flag",
	UnitType.FIVE_STAR: "Five-Star General",
	UnitType.FOUR_STAR: "Four-Star General",
	UnitType.THREE_STAR: "Three-Star General",
	UnitType.COLONEL: "Colonel",
	UnitType.MAJOR: "Major",
	UnitType.LIEUTENANT: "Lieutenant",
	UnitType.SERGEANT: "Sergeant",
	UnitType.SPY: "Spy",
	UnitType.TRAPO: "Trapo",
	UnitType.PRIVATE: "Private"
}

const UNIT_MOVEMENT := {
	UnitType.FLAG: 0,
	UnitType.FIVE_STAR: 1,
	UnitType.FOUR_STAR: 1,
	UnitType.THREE_STAR: 1,
	UnitType.COLONEL: 1,
	UnitType.MAJOR: 1,
	UnitType.LIEUTENANT: 1,
	UnitType.SERGEANT: 1,
	UnitType.SPY: 1,
	UnitType.TRAPO: 1,
	UnitType.PRIVATE: 1
}

#const AI_TEST_LAYOUT := [
#	{"pos": Vector2i(0, 0), "type": UnitType.FLAG},
#	{"pos": Vector2i(1, 0), "type": UnitType.FIVE_STAR},
#	{"pos": Vector2i(2, 0), "type": UnitType.FOUR_STAR},
#	{"pos": Vector2i(3, 0), "type": UnitType.THREE_STAR},
#	{"pos": Vector2i(4, 0), "type": UnitType.COLONEL},
#	{"pos": Vector2i(5, 0), "type": UnitType.MAJOR},
#	{"pos": Vector2i(6, 0), "type": UnitType.LIEUTENANT},
#	{"pos": Vector2i(7, 0), "type": UnitType.SERGEANT},
#	{"pos": Vector2i(8, 0), "type": UnitType.SPY},
#	{"pos": Vector2i(0, 1), "type": UnitType.TRAPO},
#	{"pos": Vector2i(1, 1), "type": UnitType.PRIVATE}
#]

const TURN_NAMES := {
	GameManager.PlayTurn.PLAYER1: "PLAYER TURN",
	GameManager.PlayTurn.AI: "AI TURN"
}

func _ready():
	initialize_counts()
	create_board()
	setup_ai_enemy()
	add_child(game_manager)
	add_child(bayesian)
	bayesian.initialise(self, arbiter, unit_behavior)
	add_child(ai_controller)
	ai_controller.initialise(bayesian, arbiter, unit_behavior, rows, columns)

	# Register every player unit slot so the Bayesian AI has priors from turn 1.
	# (Player units don't exist yet in setup phase, so we register AI units instead
	#  to seed the pool-accounting pass.)
	_register_all_player_units_with_bayesian()
	update_fog_of_war()
	emit_signal("bounty_changed", game_manager.trapo_wallet, 0, "")
	emit_signal("turn_changed", get_current_turn_name())
	emit_log("Setup phase started. Place your units on the bottom %d rows." % DEPLOYMENT_ROWS)
	# If the random start is the AI's turn, queue it up.
	if game_manager.current_turn == GameManager.PlayTurn.AI:
		ai_turn_pending = true

func initialize_counts():
	for unit_name in UNIT_ORDER:
		placed_counts[UnitType[unit_name]] = 0

func create_board():
	for y in rows:
		for x in columns:
			var tile = tile_scene.instantiate()
			grid.add_child(tile)

			var pos = Vector2i(x, y)
			tile.setup(pos, y < int(rows / 2))

			tile.tile_clicked.connect(_on_tile_clicked)

			tile_map[pos] = tile

func _process(_delta):
	# If the AI's turn was queued (after end_turn or random first-turn), execute it now.
	# We defer to _process so the UI has a frame to update before the move fires.
	if ai_turn_pending and setup_locked and not game_manager.game_over:
		ai_turn_pending = false
		run_ai_turn()

	# Poll whether the background AI thread has finished computing its move.
	if _ai_decision_pending:
		_poll_ai_thread()

	var available_size = size
	if available_size.x <= 0 or available_size.y <= 0:
		return

	var tile_size = int(floor(min(available_size.x / columns, available_size.y / rows)))
	tile_size = max(tile_size, 1)

	for child in grid.get_children():
		child.custom_minimum_size = Vector2(tile_size, tile_size)

	grid.custom_minimum_size = Vector2(tile_size * columns, tile_size * rows)

func _on_tile_clicked(pos: Vector2i):
	if bribe_mode:
		bribe_mode = false
		attempt_bribe(selected_tile, pos)
		selected_tile = pos
		emit_selected_tile_info(pos)
		highlight_tiles()
		return

	selected_tile = pos
	print("Selected:", pos)

	# Setup phase: place units
	if not setup_locked:
		# If we have a pickup in progress, try to place it
		if pickup_entry != null:
			# placing a previously picked-up unit
			if not is_in_deployment_zone(pos):
				emit_log("Blocked: You can only place units in the bottom %d rows." % DEPLOYMENT_ROWS)
				return
			# place the pickup_entry at new pos
			unit_map[pos] = pickup_entry
			var tile = tile_map[pos]
			tile.set_unit(get_unit_texture_for_entry(pickup_entry))
			emit_log("Moved placed unit %s from (%d, %d) to (%d, %d) during setup." % [get_display_name(get_unit_name_from_type(pickup_entry.type)), pickup_src_pos.x + 1, pickup_src_pos.y + 1, pos.x + 1, pos.y + 1])
			# clear pickup state
			pickup_entry = null
			pickup_src_pos = Vector2i(-1, -1)
			update_fog_of_war()
			emit_selected_tile_info(pos)
			highlight_tiles()
			return
		# If clicking a placed unit, pick it up for repositioning
		if unit_map.has(pos):
			pickup_entry = unit_map[pos]
			pickup_src_pos = pos
			# remove from board but keep counts unchanged (we're repositioning)
			unit_map.erase(pos)
			_clear_tile_at(pos)
			emit_log("Picked up %s from (%d, %d) — click destination to reposition." % [get_display_name(get_unit_name_from_type(pickup_entry.type)), pos.x + 1, pos.y + 1])
			update_fog_of_war()
			emit_selected_tile_info(pos)
			highlight_tiles()
			return
		# otherwise regular placement flow
		place_unit(pos)
		emit_selected_tile_info(pos)
		highlight_tiles()
		return

	# Battle phase: tap-to-move flow
	# Hard lock — player cannot move any pieces during the AI's turn.
	if game_manager.current_turn == GameManager.PlayTurn.AI:
		emit_log("Blocked: It is the AI's turn. Wait for the AI to finish.")
		return

	# 1) If no armed unit, arm the tapped unit (if any) provided it hasn't moved
	if armed_unit_pos.x == -1:
		if unit_map.has(pos):
			var tapped_entry = unit_map[pos]
			# Allow arming if the unit is owned by PLAYER, OR if it is a temporarily bribed unit
			if get_entry_owner(tapped_entry) != GameConstants.Team.PLAYER:
				emit_selected_tile_info(pos)
				return
			# ONE MOVE PER TURN: block arming if the player already moved this turn
			if has_moved_this_turn:
				emit_log("You already moved a piece this turn. Press 'End Turn'.")
				return
			if moved_uids.has(tapped_entry.uid):
				emit_log("Unit already moved this turn.")
				return
			armed_unit_pos = pos
			emit_log("Armed %s for movement at (%d, %d).%s" % [
				get_display_name(get_unit_name_from_type(tapped_entry.type)),
				pos.x + 1, pos.y + 1,
				_bribe_moves_label(tapped_entry.uid)
			])
			emit_selected_tile_info(pos)
			return
		else:
			# nothing to arm
			return

	# 2) If we have an armed unit, attempt to move to tapped pos
	# TOUCH-MOVE RULE: clicking the armed unit again does NOT cancel — the player must move it
	if pos == armed_unit_pos:
		emit_log("Touch-move rule: you must move this piece to a valid square.")
		emit_selected_tile_info(pos)
		return

	var src = armed_unit_pos
	if not unit_map.has(src):
		armed_unit_pos = Vector2i(-1, -1)
		return

	var entry = unit_map[src]

	# FRIENDLY FIRE PREVENTION: block movement onto a tile occupied by a friendly unit
	if unit_map.has(pos):
		var target_entry = unit_map[pos]
		if get_entry_owner(entry) == get_entry_owner(target_entry):
			emit_log("Blocked: Cannot move onto a friendly unit.")
			return

	var move_range = unit_behavior.get_move_range(unit_type_to_rank(entry.type))
	var dist = src.distance_to(pos)
	if dist > move_range:
		emit_log("Blocked: Destination out of range.")
		return

	# perform move — set has_moved_this_turn AFTER a successful move
	_move_unit(src, pos)
	has_moved_this_turn = true  # ONE MOVE PER TURN: lock further movement until end_turn()
	armed_unit_pos = Vector2i(-1, -1)
	emit_selected_tile_info(pos)
	highlight_tiles()

func place_unit(pos: Vector2i):
	if setup_locked:
		emit_log("Blocked: Setup is locked. Battle phase has started.")
		return

	if not is_in_deployment_zone(pos):
		emit_log("Blocked: You can only place units in the bottom %d rows." % DEPLOYMENT_ROWS)
		return

	var had_existing_unit := unit_map.has(pos)
	var existing_entry = unit_map[pos] if had_existing_unit else null
	var existing_type = existing_entry.type if existing_entry else null

	if not can_place_selected_unit(existing_type):
		var unit_name = get_display_name(get_selected_unit_name())
		emit_log("Blocked: No remaining %s to place." % unit_name)
		return

	if had_existing_unit and existing_type != selected_unit:
		placed_counts[existing_type] -= 1

	if not had_existing_unit or existing_type != selected_unit:
		placed_counts[selected_unit] += 1

	var entry = {"type": selected_unit, "uid": next_unit_uid}
	entry["owner"] = GameConstants.Team.PLAYER
	next_unit_uid += 1
	unit_map[pos] = entry

	var tile = tile_map[pos]

	# convert unit → image path (temporary hardcoded version)
	tile.set_unit(get_unit_texture_for_entry(entry, pos))

	var selected_name = get_display_name(get_selected_unit_name())
	var remaining_for_selected = get_remaining_for_unit(selected_unit)
	emit_log("Placed %s at (%d, %d). Remaining: %d" % [selected_name, pos.x + 1, pos.y + 1, remaining_for_selected])
	update_fog_of_war()

	if remaining_for_selected == 0:
		emit_log("%s is fully placed." % selected_name)

	if get_total_remaining_units() == 0:
		emit_log("All units placed. Setup complete.")

func is_in_deployment_zone(pos: Vector2i) -> bool:
	return pos.y >= rows - DEPLOYMENT_ROWS

func can_place_selected_unit(existing_unit) -> bool:
	if existing_unit == selected_unit:
		return true

	var limit = UNIT_LIMITS.get(selected_unit, 0)
	var current_count = placed_counts.get(selected_unit, 0)
	return current_count < limit

func get_unit_names() -> Array[String]:
	return UNIT_ORDER

func set_selected_unit_by_name(unit_name: String):
	if UnitType.has(unit_name):
		selected_unit = UnitType[unit_name]

func get_selected_unit_name() -> String:
	for unit_name in UNIT_ORDER:
		if UnitType[unit_name] == selected_unit:
			return unit_name
	return "UNKNOWN"

func get_remaining_for_unit(unit: UnitType) -> int:
	var limit = UNIT_LIMITS.get(unit, 0)
	var placed = placed_counts.get(unit, 0)
	return max(limit - placed, 0)

func get_total_remaining_units() -> int:
	var total := 0
	for unit_name in UNIT_ORDER:
		var unit: UnitType = UnitType[unit_name]
		total += get_remaining_for_unit(unit)
	return total

func is_setup_complete() -> bool:
	return get_total_remaining_units() == 0

func lock_setup_phase() -> bool:
	if setup_locked:
		return true

	if not is_setup_complete():
		emit_log("Blocked: You must place all units before starting battle phase.")
		return false

	setup_locked = true
	if game_manager:
		game_manager.timer_active = true
	emit_log("Setup phase complete. Battle phase started.")
	emit_signal("phase_changed", "battle")
	return true

func start_bribe_mode() -> void:
	if not setup_locked:
		emit_log("Blocked: Start battle phase before using Bribe.")
		return
	if game_manager.current_turn != GameManager.PlayTurn.PLAYER1:
		emit_log("Blocked: Bribe is available on your turn only.")
		return
	if selected_tile.x == -1 or not unit_map.has(selected_tile):
		emit_log("Select a Trapo unit before using Bribe.")
		return
	var selected_entry = unit_map[selected_tile]
	if get_entry_owner(selected_entry) != GameConstants.Team.PLAYER or get_unit_name_from_type(selected_entry.type) != "TRAPO":
		emit_log("Select your Trapo unit before using Bribe.")
		return
	bribe_mode = true
	emit_log("Bribe mode active. Click an enemy unit within Trapo range.")

func attempt_bribe(source_pos: Vector2i, target_pos: Vector2i) -> bool:
	if source_pos.x == -1 or not unit_map.has(source_pos):
		emit_log("Bribe cancelled: select a Trapo first.")
		return false
	if not unit_map.has(target_pos):
		emit_log("Bribe failed: choose an enemy unit.")
		return false

	var source_entry = unit_map[source_pos]
	var target_entry = unit_map[target_pos]
	if get_entry_owner(source_entry) != GameConstants.Team.PLAYER or get_unit_name_from_type(source_entry.type) != "TRAPO":
		emit_log("Bribe failed: source unit must be your Trapo.")
		return false
	if get_entry_owner(target_entry) != GameConstants.Team.AI:
		emit_log("Bribe failed: target must be an enemy unit.")
		return false

	var target_rank = unit_type_to_rank(target_entry.type)
	if not unit_behavior.can_corrupt(source_pos, target_pos, target_rank):
		emit_log("Bribe failed: target is out of Trapo range or cannot be bribed.")
		return false
	if not game_manager.bribe_enemy(target_rank):
		emit_log("Bribe failed: not enough credits to reveal the selected enemy unit.")
		return false

	# --- BRIBE SUCCESS ---
	# 1. Switch ownership to PLAYER for the duration of the bribe.
	target_entry["owner"] = GameConstants.Team.PLAYER
	unit_map[target_pos] = target_entry

	# 2. Register the unit in the bribed tracker with its move budget.
	bribed_units[target_entry.uid] = {
		"moves_remaining": BRIBE_MOVE_DURATION,
		"original_owner": GameConstants.Team.AI
	}

	# 3. Fully reveal the unit to the bribing player (sprite + rank panel).
	revealed_enemy_tiles[target_pos] = true
	revealed_rank_only[target_pos] = target_rank

	# 4. Update the tile sprite so it shows the real unit texture (not Enemy.png).
	tile_map[target_pos].set_unit(get_unit_texture(target_entry.type))

	# ── BAYESIAN: bribe reveals the exact rank of this unit ──
	bayesian.update_from_bribe_reveal(target_entry.uid, target_rank)

	emit_log("Bribe successful! %s is now under your control for %d moves." % [
		UNIT_RANK_NAMES.get(target_entry.type, "Unknown"),
		BRIBE_MOVE_DURATION
	])
	emit_signal("bounty_changed", game_manager.trapo_wallet, 0, "")
	update_fog_of_war()
	emit_selected_tile_info(target_pos)
	return true

# Returns a human-readable label showing remaining bribe moves, or "" if not bribed.
func _bribe_moves_label(uid: int) -> String:
	if bribed_units.has(uid):
		return " [Bribed: %d move(s) left]" % bribed_units[uid]["moves_remaining"]
	return ""

# Called after a bribed unit successfully moves. Decrements its move counter and
# reverts ownership when the budget is exhausted.
func _tick_bribe_for_unit(uid: int, current_pos: Vector2i) -> void:
	if not bribed_units.has(uid):
		return

	bribed_units[uid]["moves_remaining"] -= 1
	var remaining: int = bribed_units[uid]["moves_remaining"]

	if remaining <= 0:
		# Bribe expired — revert ownership back to the original team.
		var original_owner: GameConstants.Team = bribed_units[uid]["original_owner"]
		bribed_units.erase(uid)
		if unit_map.has(current_pos):
			var entry = unit_map[current_pos]
			if entry.uid == uid:
				entry["owner"] = original_owner
				unit_map[current_pos] = entry
				# Remove permanent reveal entries so the unit goes back into fog
				# once player vision no longer covers its tile.
				revealed_enemy_tiles.erase(current_pos)
				revealed_rank_only.erase(current_pos)
				# Restore the correct sprite for the reverted owner.
				tile_map[current_pos].set_unit(get_unit_texture_for_entry(entry, current_pos))
				var side := "the enemy" if original_owner == GameConstants.Team.AI else "you"
				emit_log("Bribe expired: %s has returned to %s." % [
					get_display_name(get_unit_name_from_type(entry.type)), side
				])
		update_fog_of_war()
	else:
		emit_log("Bribed unit has %d move(s) remaining." % remaining)

func get_display_name(unit_name: String) -> String:
	var words = unit_name.to_lower().split("_")
	for i in words.size():
		words[i] = words[i].capitalize()
	return " ".join(words)

func emit_log(message: String):
	print(message)
	emit_signal("log_message", message)

func emit_selected_tile_info(pos: Vector2i):
	if not unit_map.has(pos):
		emit_signal("selected_tile_unit_info", "", "", "", "")
		return

	var entry = unit_map[pos]
	var unit: UnitType = entry.type
	# If this is an AI-owned unit and fog is enabled, only show details when
	# the tile was successfully bribed (revealed_rank_only). Bribed units that
	# are temporarily player-controlled will have owner == PLAYER so they fall
	# through to the full-info block below automatically.
	if get_entry_owner(entry) == GameConstants.Team.AI and game_manager.fog_of_war_enabled():
		if revealed_rank_only.has(pos):
			var unit_name = get_unit_name_from_type(unit)
			var rank = UNIT_RANK_NAMES.get(unit, "Unknown")
			var rank_value = unit_type_to_rank(unit)
			var vision = str(game_manager.visible_tiles_for_piece(rank_value))
			var movement = str(unit_behavior.get_move_range(rank_value))
			emit_signal("selected_tile_unit_info", unit_name, rank, vision, movement)
			return
		emit_signal("selected_tile_unit_info", "", "", "", "")
		return

	var unit_name = get_unit_name_from_type(unit)
	var rank = UNIT_RANK_NAMES.get(unit, "Unknown")
	var rank_value = unit_type_to_rank(unit)
	var vision = str(game_manager.visible_tiles_for_piece(rank_value))
	var movement = str(unit_behavior.get_move_range(rank_value))
	emit_signal("selected_tile_unit_info", unit_name, rank, vision, movement)

func _is_enemy_revealed_or_visible(pos: Vector2i) -> bool:
	return revealed_enemy_tiles.has(pos) or is_tile_visible_to_player(pos)

func _clear_tile_at(pos: Vector2i):
	if tile_map.has(pos):
		tile_map[pos].set_unit("")

func _move_unit(src: Vector2i, dst: Vector2i):
	var entry = unit_map[src]
	var attacker_rank = unit_type_to_rank(entry.type)

	if unit_map.has(dst):
		var defender_entry = unit_map[dst]

		# FRIENDLY FIRE PREVENTION: block moves onto tiles occupied by the same team.
		# This also prevents bribed (temporarily player-owned) units from attacking
		# their temporary allies, and prevents the original team from eating them.
		if get_entry_owner(entry) == get_entry_owner(defender_entry):
			emit_log("Blocked: Cannot move onto a friendly unit.")
			return

		var defender_rank = unit_type_to_rank(defender_entry.type)
		var combat_result = arbiter.resolve_combat(attacker_rank, defender_rank)
		var bounty_awarded := 0
		var bounty_unit_name := ""

		if combat_result == Arbiter.CombatResult.ATTACKER_WINS or combat_result == Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS:
				bounty_awarded = _maybe_award_bounty(defender_entry, entry)
				if bounty_awarded > 0:
					bounty_unit_name = "Enemy Unit"
				# If the defender was a bribed unit that got killed, clean up its bribe record.
				if bribed_units.has(defender_entry.uid):
					bribed_units.erase(defender_entry.uid)
				# ── BAYESIAN: combat reveals relative rank of the losing unit ──
				var _ai_is_attacker = get_entry_owner(entry) == GameConstants.Team.AI
				if _ai_is_attacker:
					# AI attacked and won → player defender rank was below AI attacker rank
					bayesian.update_from_combat(attacker_rank, defender_entry.uid, combat_result, true)
				else:
					# Player attacked and won → player attacker rank was above AI defender rank
					bayesian.update_from_combat(defender_rank, entry.uid, combat_result, false)
				unit_map.erase(src)
				_clear_tile_at(src)
				unit_map.erase(dst)
				revealed_enemy_tiles.erase(dst)
				revealed_rank_only.erase(dst)
				unit_map[dst] = entry
				tile_map[dst].set_unit(get_unit_texture_for_entry(entry, dst))
				moved_uids.append(entry.uid)
				emit_log(
					get_fog_combat_message(
						combat_result,
						get_entry_owner(entry) == GameConstants.Team.PLAYER,
						entry,
						defender_entry
					)
				)
				# Tick bribe counter for the attacker after a successful combat move.
				_tick_bribe_for_unit(entry.uid, dst)
				if combat_result == Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS:
					game_manager.game_over = true
					emit_log("Game over: attacker captured the flag.")
		elif combat_result == Arbiter.CombatResult.DEFENDER_WINS or combat_result == Arbiter.CombatResult.GAME_OVER_DEFENDER_WINS:
			bounty_awarded = _maybe_award_bounty(entry, defender_entry)
			if bounty_awarded > 0:
				bounty_unit_name = get_unit_name_from_type(entry.type)
			# Attacker was killed — clean up its bribe record if it had one.
			if bribed_units.has(entry.uid):
				bribed_units.erase(entry.uid)
			# ── BAYESIAN: defender won → attacker rank was below defender rank ──
			var _ai_is_attacker_dw = get_entry_owner(entry) == GameConstants.Team.AI
			if _ai_is_attacker_dw:
				# AI attacked and lost → player defender rank was above AI attacker rank
				bayesian.update_from_combat(attacker_rank, defender_entry.uid, combat_result, true)
			else:
				# Player attacked and lost → player attacker rank was below AI defender rank
				bayesian.update_from_combat(defender_rank, entry.uid, combat_result, false)
			unit_map.erase(src)
			_clear_tile_at(src)
			moved_uids.append(entry.uid)
			emit_log(
				get_fog_combat_message(
					combat_result,
					get_entry_owner(entry) == GameConstants.Team.PLAYER,
					entry,
					defender_entry
				)
			)
			if combat_result == Arbiter.CombatResult.GAME_OVER_DEFENDER_WINS:
				game_manager.game_over = true
				emit_log("Game over: defender kept the flag.")
		elif combat_result == Arbiter.CombatResult.TIE:
			var attacker_bounty: int = _maybe_award_bounty(defender_entry, entry)
			if attacker_bounty > 0:
				bounty_awarded = attacker_bounty
				bounty_unit_name = get_unit_name_from_type(defender_entry.type)
			else:
				var defender_bounty: int = _maybe_award_bounty(entry, defender_entry)
				if defender_bounty > 0:
					bounty_awarded = defender_bounty
					bounty_unit_name = get_unit_name_from_type(entry.type)
			# Both died — clean up bribe records for both.
			if bribed_units.has(entry.uid):
				bribed_units.erase(entry.uid)
			if bribed_units.has(defender_entry.uid):
				bribed_units.erase(defender_entry.uid)
			# ── BAYESIAN: tie → both units share the same rank (pins exactly) ──
			var _ai_is_attacker_tie = get_entry_owner(entry) == GameConstants.Team.AI
			if _ai_is_attacker_tie:
				bayesian.update_from_combat(attacker_rank, defender_entry.uid, combat_result, true)
			else:
				bayesian.update_from_combat(defender_rank, entry.uid, combat_result, false)
			unit_map.erase(src)
			_clear_tile_at(src)
			unit_map.erase(dst)
			_clear_tile_at(dst)
			moved_uids.append(entry.uid)
			emit_log(
				get_fog_combat_message(
					combat_result,
					get_entry_owner(entry) == GameConstants.Team.PLAYER,
					entry,
					defender_entry
				)
			)
		if bounty_awarded > 0:
			emit_signal("bounty_changed", game_manager.trapo_wallet, bounty_awarded, bounty_unit_name)
		update_fog_of_war()
		return

	# No defender — plain move to empty tile.
	unit_map.erase(src)
	_clear_tile_at(src)
	revealed_enemy_tiles.erase(src)
	revealed_rank_only.erase(src)

	unit_map[dst] = entry
	var tile_dst = tile_map[dst]
	revealed_enemy_tiles.erase(dst)
	revealed_rank_only.erase(dst)
	tile_dst.set_unit(get_unit_texture_for_entry(entry, dst))

	moved_uids.append(entry.uid)
	# Only reveal the unit name in the log if it belongs to the player.
	# AI unit names must stay hidden — just say "An enemy unit moved."
	if get_entry_owner(entry) == GameConstants.Team.PLAYER:
		emit_log("Moved %s from (%d, %d) to (%d, %d).%s" % [
			get_display_name(get_unit_name_from_type(entry.type)),
			src.x + 1, src.y + 1, dst.x + 1, dst.y + 1,
			_bribe_moves_label(entry.uid)
		])
	else:
		emit_log("An enemy unit moved.")

	# ── BAYESIAN: update position & aggression/avoidance beliefs on plain moves ──
	if get_entry_owner(entry) == GameConstants.Team.PLAYER:
		bayesian.register_player_unit(entry.uid)
		bayesian.update_from_position(entry.uid, dst, rows)
		# Moving toward the AI's half (lower y) signals aggression.
		if dst.y < src.y:
			bayesian.update_from_aggression(entry.uid)
		# Moving away from the AI's half signals avoidance.
		elif dst.y > src.y:
			bayesian.update_from_avoidance(entry.uid)

	# Tick the bribe counter for this unit now that it has moved.
	_tick_bribe_for_unit(entry.uid, dst)

	update_fog_of_war()

func _maybe_award_bounty(killed_entry: Dictionary, killer_entry: Dictionary) -> int:
	print("DEBUG: _maybe_award_bounty called -- killed_entry=", killed_entry, " killer_entry=", killer_entry)
	if typeof(killed_entry) != TYPE_DICTIONARY or typeof(killer_entry) != TYPE_DICTIONARY:
		print("DEBUG: _maybe_award_bounty returning 0: invalid types")
		return 0
	var killed_owner = get_entry_owner(killed_entry)
	var killer_owner = get_entry_owner(killer_entry)
	print("DEBUG: killed_owner=", killed_owner, " killer_owner=", killer_owner)
	if killed_owner != GameConstants.Team.AI:
		print("DEBUG: _maybe_award_bounty returning 0: killed is not AI")
		return 0
	if killer_owner != GameConstants.Team.PLAYER:
		print("DEBUG: _maybe_award_bounty returning 0: killer is not PLAYER")
		return 0

	var killed_rank: GameConstants.Rank = unit_type_to_rank(killed_entry.type)
	print("DEBUG: killed_rank=", killed_rank)
	var bounty: int = 0
	if GameConstants.BOUNTIES.has(killed_rank):
		bounty = GameConstants.BOUNTIES[killed_rank]
	else:
		print("DEBUG: no bounty defined for rank=", killed_rank)
	if bounty > 0:
		print("DEBUG: awarding bounty - killed_rank=", killed_rank, " bounty=", bounty, " wallet_before=", game_manager.trapo_wallet)
		game_manager.add_kill_bounty(killed_rank)
		print("DEBUG: wallet_after=", game_manager.trapo_wallet)
		return bounty
	print("DEBUG: _maybe_award_bounty returning 0: bounty is 0 for killed_rank=", killed_rank)
	return 0

func end_turn():
	game_manager.switch_turn()
	turn_number += 1
	moved_uids.clear()
	has_moved_this_turn = false  # ONE MOVE PER TURN: reset so the player can move again next turn
	armed_unit_pos = Vector2i(-1, -1)
	bribe_mode = false
	emit_signal("turn_changed", get_current_turn_name())
	emit_log("Turn ended. Movement reset.")
	# Queue the AI turn; it will fire on the next _process frame.
	if game_manager.current_turn == GameManager.PlayTurn.AI:
		bayesian.tick_idle()
		_register_all_player_units_with_bayesian()
		ai_turn_pending = true

# =============================================================================
# AI TURN — driven by BayesianAI
# =============================================================================

## Registers every currently-visible player unit with the Bayesian AI so it
## builds priors even before any combat evidence arrives.
func _register_all_player_units_with_bayesian() -> void:
	for pos in unit_map.keys():
		var entry = unit_map[pos]
		if get_entry_owner(entry) == GameConstants.Team.PLAYER:
			bayesian.register_player_unit(entry.uid)
			bayesian.update_from_position(entry.uid, pos, rows)

# Thread used to run MCTS off the main thread so the timer and UI keep ticking.
var _ai_thread: Thread = null
var _ai_decision_pending: bool = false
var _ai_decision: Dictionary = {}

## Starts the AI turn on a background thread so _process() / timers are not blocked.
func run_ai_turn() -> void:
	if game_manager.game_over:
		return
	if game_manager.current_turn != GameManager.PlayTurn.AI:
		return

	emit_log("AI is thinking…")

	# Snapshot the wallet now so the thread uses a consistent value.
	var wallet_snapshot: int = game_manager.trapo_wallet
	# Deep-clone the unit_map so the thread works on its own copy and does not
	# race with any main-thread reads.
	var map_snapshot: Dictionary = {}
	for pos in unit_map.keys():
		map_snapshot[pos] = unit_map[pos].duplicate()

	_ai_thread = Thread.new()
	_ai_thread.start(_ai_thread_func.bind(map_snapshot, wallet_snapshot))

## Called every frame — checks if the AI thread has finished and applies the result.
func _poll_ai_thread() -> void:
	if _ai_thread == null or not _ai_decision_pending:
		return
	_ai_decision_pending = false
	_ai_thread.wait_to_finish()
	_ai_thread = null
	_apply_ai_decision(_ai_decision)

## Runs on the background thread — only pure computation, no scene-tree calls.
func _ai_thread_func(map_snapshot: Dictionary, wallet_snapshot: int) -> void:
	var decision = ai_controller.choose_move(map_snapshot, rows, columns, wallet_snapshot)
	_ai_decision = decision
	_ai_decision_pending = true

## Applies the AI decision on the main thread (called from _poll_ai_thread).
func _apply_ai_decision(decision: Dictionary) -> void:
	match decision.action:
		"move":
			var src: Vector2i = decision.src
			var dst: Vector2i = decision.dst
			if src == Vector2i(-1, -1) or dst == Vector2i(-1, -1):
				emit_log("AI has no valid moves this turn.")
			elif unit_map.has(src):
				_move_unit(src, dst)
			else:
				emit_log("AI move source no longer valid.")

		"bribe":
			# AI Trapo bribes a player unit.
			# The unit's owner stays PLAYER — it is temporarily controlled by AI
			# (same pattern as when the player bribes an AI unit: owner flips to
			# PLAYER).  We must NOT change owner to AI here, otherwise
			# update_fog_of_war / get_unit_texture_for_entry would treat it as an
			# AI unit and either hide it under fog or expose its real sprite.
			var trapo_pos: Vector2i = decision.src
			var target_pos: Vector2i = decision.dst
			if unit_map.has(trapo_pos) and unit_map.has(target_pos):
				var target_entry = unit_map[target_pos]
				var target_rank = unit_type_to_rank(target_entry.type)
				if game_manager.bribe_enemy(target_rank):
					# Keep owner as PLAYER — the unit is bribed but visually stays
					# on the player's side (fog rules already apply correctly).
					bribed_units[target_entry.uid] = {
						"moves_remaining": BRIBE_MOVE_DURATION,
						"original_owner": GameConstants.Team.PLAYER
					}
					# Do NOT add to revealed_enemy_tiles — the AI has no business
					# exposing the player unit's rank on screen.
					emit_log("AI Trapo bribed your %s! It will serve the enemy for %d moves." % [
						UNIT_RANK_NAMES.get(target_entry.type, "unit"), BRIBE_MOVE_DURATION
					])
					emit_signal("bounty_changed", game_manager.trapo_wallet, 0, "")
					update_fog_of_war()
				else:
					emit_log("AI Trapo wanted to bribe but lacked credits.")
			else:
				emit_log("AI bribe target no longer valid.")

		_:
			emit_log("AI skips this turn.")

	# Hand control back to the player.
	end_turn()

func get_unit_name_from_type(unit: UnitType) -> String:
	for unit_name in UNIT_ORDER:
		if UnitType[unit_name] == unit:
			return unit_name
	return "UNKNOWN"

func get_current_turn_name() -> String:
	return TURN_NAMES.get(game_manager.current_turn, "PLAYER TURN")

func unit_type_to_rank(unit: UnitType) -> GameConstants.Rank:
	match unit:
		UnitType.FLAG:
			return GameConstants.Rank.FLAG
		UnitType.FIVE_STAR:
			return GameConstants.Rank.GENERAL_5
		UnitType.FOUR_STAR:
			return GameConstants.Rank.GENERAL_4
		UnitType.THREE_STAR:
			return GameConstants.Rank.GENERAL_3
		UnitType.COLONEL:
			return GameConstants.Rank.COLONEL
		UnitType.MAJOR:
			return GameConstants.Rank.MAJOR
		UnitType.LIEUTENANT:
			return GameConstants.Rank.LIEUTENANT
		UnitType.SERGEANT:
			return GameConstants.Rank.SERGEANT
		UnitType.SPY:
			return GameConstants.Rank.SPY
		UnitType.TRAPO:
			return GameConstants.Rank.TRAPO
		UnitType.PRIVATE:
			return GameConstants.Rank.PRIVATE
	return GameConstants.Rank.FLAG

func get_turn_number() -> int:
	return turn_number

#yung naunang code before yung randomized smth
#func setup_ai_enemy():
#	for unit_data in AI_TEST_LAYOUT:
#		var pos: Vector2i = unit_data["pos"]
#		if not tile_map.has(pos):
#			continue
#		var entry = {
#			"type": unit_data["type"],
#			"uid": next_unit_uid,
#			"owner": GameConstants.Team.AI
#		}
#		next_unit_uid += 1
#		unit_map[pos] = entry
#		tile_map[pos].set_unit(get_unit_texture_for_entry(entry, pos))

func setup_ai_enemy():
	var available_positions = []
	# AI deploys in top 4 rows
	for y in range(DEPLOYMENT_ROWS):
		for x in range(columns):
			available_positions.append(Vector2i(x, y))
	available_positions.shuffle()
	var ai_units = [
		UnitType.FLAG,
		UnitType.FIVE_STAR,
		UnitType.FOUR_STAR,
		UnitType.THREE_STAR,
		UnitType.COLONEL,
		UnitType.MAJOR,
		UnitType.LIEUTENANT,
		UnitType.SERGEANT,
		UnitType.SPY,
		UnitType.SPY,
		UnitType.TRAPO
	]
	for i in range(7):
		ai_units.append(UnitType.PRIVATE)
	ai_units.shuffle()
	for i in range(ai_units.size()):
		var pos = available_positions[i]
		var entry = {
			"type": ai_units[i],
			"uid": next_unit_uid,
			"owner": GameConstants.Team.AI
		}
		next_unit_uid += 1
		unit_map[pos] = entry
		tile_map[pos].set_unit(
			get_unit_texture_for_entry(entry, pos)
		)

func update_fog_of_war():
	if not game_manager.fog_of_war_enabled():
		for pos in tile_map.keys():
			tile_map[pos].set_fog_visible(false)
		return

	var top_half_limit := int(rows / 2)
	for pos in tile_map.keys():
		var should_show_fog: bool = pos.y < top_half_limit and not is_tile_visible_to_player(pos) and not revealed_enemy_tiles.has(pos)
		tile_map[pos].set_fog_visible(should_show_fog)

func is_tile_visible_to_player(target_pos: Vector2i) -> bool:
	for observer_pos in unit_map.keys():
		var entry = unit_map[observer_pos]
		if get_entry_owner(entry) != GameConstants.Team.PLAYER:
			continue
		if unit_behavior.is_enemy_visible(observer_pos, target_pos, unit_type_to_rank(entry.type)):
			return true
	return false

func get_entry_owner(entry) -> GameConstants.Team:
	if typeof(entry) == TYPE_DICTIONARY and entry.has("owner"):
		return entry.owner
	return GameConstants.Team.PLAYER

func get_unit_texture_for_entry(entry, pos: Vector2i = Vector2i(-1, -1)) -> String:
	# Bribed units are temporarily owned by PLAYER — show their real sprite so the
	# player knows what they control. Once the bribe expires and owner reverts to AI,
	# this path is no longer taken and they fall back into fog normally.
	if get_entry_owner(entry) == GameConstants.Team.AI and game_manager.fog_of_war_enabled():
		if pos == Vector2i(-1, -1) or not _is_enemy_revealed_or_visible(pos):
			return "res://assets/units/Enemy.png"
	return get_unit_texture(entry.type)

func highlight_tiles():
	for pos in tile_map.keys():
		tile_map[pos].set_selected(pos == selected_tile)


func get_unit_texture(unit: UnitType) -> String:
	match unit:
		UnitType.FLAG:
			return "res://assets/units/Flag.png"
		UnitType.FIVE_STAR:
			return "res://assets/units/Five-Star General.png"
		UnitType.FOUR_STAR:
			return "res://assets/units/Four-Star General.png"
		UnitType.THREE_STAR:
			return "res://assets/units/Three-Star General.png"
		UnitType.COLONEL:
			return "res://assets/units/Colonel.png"
		UnitType.MAJOR:
			return "res://assets/units/Major.png"
		UnitType.LIEUTENANT:
			return "res://assets/units/Lieutenant.png"
		UnitType.SERGEANT:
			return "res://assets/units/Sergeant.png"
		UnitType.SPY:
			return "res://assets/units/Spy.png"
		UnitType.TRAPO:
			return "res://assets/units/Trapo.png"
		UnitType.PRIVATE:
			return "res://assets/units/Private.png"
	return ""

func get_fog_combat_message(
	combat_result: Arbiter.CombatResult,
	attacker_is_player: bool,
	attacker_entry: Dictionary,
	defender_entry: Dictionary
) -> String:

	# Only reveal the name of a unit if it belongs to the PLAYER.
	# AI unit names/ranks must never appear in the log — show "enemy unit" instead.
	var player_attacker_name: String = get_display_name(
		get_unit_name_from_type(attacker_entry.type)
	) if attacker_is_player else "unit"

	var player_defender_name: String = get_display_name(
		get_unit_name_from_type(defender_entry.type)
	) if not attacker_is_player else "unit"

	match combat_result:

		Arbiter.CombatResult.ATTACKER_WINS:
			if attacker_is_player:
				return "Your %s captured an enemy unit." % player_attacker_name
			else:
				return "The enemy captured your %s." % player_defender_name

		Arbiter.CombatResult.DEFENDER_WINS:
			if attacker_is_player:
				return "Your %s was captured by an enemy unit." % player_attacker_name
			else:
				return "Your %s repelled the enemy attack." % player_defender_name

		Arbiter.CombatResult.TIE:
			if attacker_is_player:
				return "Your %s was eliminated in combat with an enemy unit." % player_attacker_name
			else:
				return "Your %s was eliminated in combat with an enemy unit." % player_defender_name

		Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS:
			if attacker_is_player:
				return "Your unit captured the enemy Flag!"
			else:
				return "The enemy captured your Flag!"

		Arbiter.CombatResult.GAME_OVER_DEFENDER_WINS:
			if attacker_is_player:
				return "Your Flag was captured."
			else:
				return "The enemy Flag was captured."

	return ""
