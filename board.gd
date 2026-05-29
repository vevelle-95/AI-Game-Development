extends Control

signal log_message(message: String)
signal selected_tile_unit_info(unit_name: String, rank: String, vision: String, movement: String)
signal phase_changed(phase_name: String)
signal turn_changed(turn_name: String)
signal bounty_changed(total_bounty: int, last_bounty: int, killed_unit_name: String)

@onready var game_manager: GameManager = GameManager.new()
@onready var unit_behavior: UnitBehavior = UnitBehavior.new()
@onready var arbiter: Arbiter = Arbiter.new()

@export var tile_scene: PackedScene
@export var columns := 9
@export var rows := 8

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
var armed_unit_pos := Vector2i(-1, -1)
var pickup_entry = null
var pickup_src_pos := Vector2i(-1, -1)
var turn_number := 1

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

const DEPLOYMENT_ROWS := 3

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

const AI_TEST_LAYOUT := [
	{"pos": Vector2i(0, 0), "type": UnitType.FLAG},
	{"pos": Vector2i(1, 0), "type": UnitType.FIVE_STAR},
	{"pos": Vector2i(2, 0), "type": UnitType.FOUR_STAR},
	{"pos": Vector2i(3, 0), "type": UnitType.THREE_STAR},
	{"pos": Vector2i(4, 0), "type": UnitType.COLONEL},
	{"pos": Vector2i(5, 0), "type": UnitType.MAJOR},
	{"pos": Vector2i(6, 0), "type": UnitType.LIEUTENANT},
	{"pos": Vector2i(7, 0), "type": UnitType.SERGEANT},
	{"pos": Vector2i(8, 0), "type": UnitType.SPY},
	{"pos": Vector2i(0, 1), "type": UnitType.TRAPO},
	{"pos": Vector2i(1, 1), "type": UnitType.PRIVATE}
]

const TURN_NAMES := {
	GameManager.PlayTurn.PLAYER1: "PLAYER TURN",
	GameManager.PlayTurn.AI: "AI TURN"
}

func _ready():
	initialize_counts()
	create_board()
	setup_ai_enemy()
	update_fog_of_war()
	emit_signal("bounty_changed", game_manager.trapo_wallet, 0, "")
	emit_signal("turn_changed", get_current_turn_name())
	emit_log("Setup phase started. Place your units on the bottom %d rows." % DEPLOYMENT_ROWS)

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
	var available_size = size
	if available_size.x <= 0 or available_size.y <= 0:
		return

	var tile_size = int(floor(min(available_size.x / columns, available_size.y / rows)))
	tile_size = max(tile_size, 1)

	for child in grid.get_children():
		child.custom_minimum_size = Vector2(tile_size, tile_size)

	grid.custom_minimum_size = Vector2(tile_size * columns, tile_size * rows)

func _on_tile_clicked(pos: Vector2i):
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
	# 1) If no armed unit, arm the tapped unit (if any) provided it hasn't moved
	if armed_unit_pos.x == -1:
		if unit_map.has(pos):
			var tapped_entry = unit_map[pos]
			if get_entry_owner(tapped_entry) != GameConstants.Team.PLAYER:
				emit_selected_tile_info(pos)
				return
			if moved_uids.has(tapped_entry.uid):
				emit_log("Unit already moved this turn.")
				return
			armed_unit_pos = pos
			emit_log("Armed %s for movement at (%d, %d)." % [get_display_name(get_unit_name_from_type(tapped_entry.type)), pos.x + 1, pos.y + 1])
			emit_selected_tile_info(pos)
			return
		else:
			# nothing to arm
			return

	# 2) If we have an armed unit, attempt to move to tapped pos
	if pos == armed_unit_pos:
		armed_unit_pos = Vector2i(-1, -1)
		emit_log("Movement cancelled.")
		emit_selected_tile_info(pos)
		return

	var src = armed_unit_pos
	if not unit_map.has(src):
		armed_unit_pos = Vector2i(-1, -1)
		return

	var entry = unit_map[src]
	var move_range = unit_behavior.get_move_range(unit_type_to_rank(entry.type))
	var dist = src.distance_to(pos)
	if dist > move_range:
		emit_log("Blocked: Destination out of range.")
		return

	# perform move
	_move_unit(src, pos)
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
	tile.set_unit(get_unit_texture_for_entry(entry))

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
	emit_log("Setup phase complete. Battle phase started.")
	emit_signal("phase_changed", "battle")
	return true

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
	if get_entry_owner(entry) == GameConstants.Team.AI and game_manager.fog_of_war_enabled():
		emit_signal("selected_tile_unit_info", "", "", "", "")
		return
	var unit_name = get_unit_name_from_type(unit)
	var rank = UNIT_RANK_NAMES.get(unit, "Unknown")
	var rank_value = unit_type_to_rank(unit)
	var vision = str(game_manager.visible_tiles_for_piece(rank_value))
	var movement = str(unit_behavior.get_move_range(rank_value))
	emit_signal("selected_tile_unit_info", unit_name, rank, vision, movement)

func _clear_tile_at(pos: Vector2i):
	if tile_map.has(pos):
		tile_map[pos].set_unit("")

func _move_unit(src: Vector2i, dst: Vector2i):
	var entry = unit_map[src]
	var attacker_rank = unit_type_to_rank(entry.type)

	if unit_map.has(dst):
		var defender_entry = unit_map[dst]
		var defender_rank = unit_type_to_rank(defender_entry.type)
		var combat_result = arbiter.resolve_combat(attacker_rank, defender_rank)
		var bounty_awarded := 0
		var bounty_unit_name := ""

		if combat_result == Arbiter.CombatResult.ATTACKER_WINS or combat_result == Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS:
			bounty_awarded = _maybe_award_bounty(defender_entry, entry)
			if bounty_awarded > 0:
				bounty_unit_name = get_unit_name_from_type(defender_entry.type)
			unit_map.erase(src)
			_clear_tile_at(src)
			unit_map.erase(dst)
			unit_map[dst] = entry
			tile_map[dst].set_unit(get_unit_texture_for_entry(entry))
			moved_uids.append(entry.uid)
			emit_log("Moved %s from (%d, %d) to (%d, %d) and captured %s." % [get_display_name(get_unit_name_from_type(entry.type)), src.x + 1, src.y + 1, dst.x + 1, dst.y + 1, get_display_name(get_unit_name_from_type(defender_entry.type))])
			if combat_result == Arbiter.CombatResult.GAME_OVER_ATTACKER_WINS:
				game_manager.game_over = true
				emit_log("Game over: attacker captured the flag.")
		elif combat_result == Arbiter.CombatResult.DEFENDER_WINS or combat_result == Arbiter.CombatResult.GAME_OVER_DEFENDER_WINS:
			bounty_awarded = _maybe_award_bounty(entry, defender_entry)
			if bounty_awarded > 0:
				bounty_unit_name = get_unit_name_from_type(entry.type)
			unit_map.erase(src)
			_clear_tile_at(src)
			moved_uids.append(entry.uid)
			emit_log("%s lost against %s at (%d, %d)." % [get_display_name(get_unit_name_from_type(entry.type)), get_display_name(get_unit_name_from_type(defender_entry.type)), dst.x + 1, dst.y + 1])
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
			unit_map.erase(src)
			_clear_tile_at(src)
			unit_map.erase(dst)
			_clear_tile_at(dst)
			moved_uids.append(entry.uid)
			emit_log("%s and %s eliminated each other at (%d, %d)." % [get_display_name(get_unit_name_from_type(entry.type)), get_display_name(get_unit_name_from_type(defender_entry.type)), dst.x + 1, dst.y + 1])
		if bounty_awarded > 0:
			emit_signal("bounty_changed", game_manager.trapo_wallet, bounty_awarded, bounty_unit_name)
		update_fog_of_war()
		return

	# remove from src
	unit_map.erase(src)
	_clear_tile_at(src)

	# place unit at dst
	unit_map[dst] = entry
	var tile_dst = tile_map[dst]
	tile_dst.set_unit(get_unit_texture_for_entry(entry))

	# mark moved
	moved_uids.append(entry.uid)
	emit_log("Moved %s from (%d, %d) to (%d, %d)." % [get_display_name(get_unit_name_from_type(entry.type)), src.x + 1, src.y + 1, dst.x + 1, dst.y + 1])
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
	armed_unit_pos = Vector2i(-1, -1)
	emit_signal("turn_changed", get_current_turn_name())
	emit_log("Turn ended. Movement reset.")

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

func setup_ai_enemy():
	for unit_data in AI_TEST_LAYOUT:
		var pos: Vector2i = unit_data["pos"]
		if not tile_map.has(pos):
			continue
		var entry = {
			"type": unit_data["type"],
			"uid": next_unit_uid,
			"owner": GameConstants.Team.AI
		}
		next_unit_uid += 1
		unit_map[pos] = entry
		tile_map[pos].set_unit(get_unit_texture_for_entry(entry))

func update_fog_of_war():
	if not game_manager.fog_of_war_enabled():
		for pos in tile_map.keys():
			tile_map[pos].set_fog_visible(false)
		return

	var top_half_limit := int(rows / 2)
	for pos in tile_map.keys():
		var should_show_fog: bool = pos.y < top_half_limit and not is_tile_visible_to_player(pos)
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

func get_unit_texture_for_entry(entry) -> String:
	if get_entry_owner(entry) == GameConstants.Team.AI:
		if game_manager.fog_of_war_enabled():
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
