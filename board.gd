extends Control

signal log_message(message: String)
signal selected_tile_unit_info(unit_name: String, rank: String, vision: String, movement: String)
signal phase_changed(phase_name: String)

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

func _ready():
	initialize_counts()
	create_board()
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
			tile.setup(pos)

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
			tile.set_unit(get_unit_texture(pickup_entry.type))
			emit_log("Moved placed unit %s from (%d, %d) to (%d, %d) during setup." % [get_display_name(get_unit_name_from_type(pickup_entry.type)), pickup_src_pos.x + 1, pickup_src_pos.y + 1, pos.x + 1, pos.y + 1])
			# clear pickup state
			pickup_entry = null
			pickup_src_pos = Vector2i(-1, -1)
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
	var move_range = preload("res://UnitBehavior.gd").new().get_move_range(entry.type)
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
	next_unit_uid += 1
	unit_map[pos] = entry

	var tile = tile_map[pos]

	# convert unit → image path (temporary hardcoded version)
	tile.set_unit(get_unit_texture(selected_unit))

	var selected_name = get_display_name(get_selected_unit_name())
	var remaining_for_selected = get_remaining_for_unit(selected_unit)
	emit_log("Placed %s at (%d, %d). Remaining: %d" % [selected_name, pos.x + 1, pos.y + 1, remaining_for_selected])

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
	var unit_name = get_unit_name_from_type(unit)
	var rank = UNIT_RANK_NAMES.get(unit, "Unknown")
	var movement = str(UNIT_MOVEMENT.get(unit, 0))
	emit_signal("selected_tile_unit_info", unit_name, rank, "", movement)

func _clear_tile_at(pos: Vector2i):
	if tile_map.has(pos):
		tile_map[pos].set_unit("")

func _move_unit(src: Vector2i, dst: Vector2i):
	var entry = unit_map[src]
	# remove from src
	unit_map.erase(src)
	_clear_tile_at(src)

	# if destination had unit, decrement its count
	if unit_map.has(dst):
		var dest_entry = unit_map[dst]
		placed_counts[dest_entry.type] -= 1

	# place unit at dst
	unit_map[dst] = entry
	var tile_dst = tile_map[dst]
	tile_dst.set_unit(get_unit_texture(entry.type))

	# mark moved
	moved_uids.append(entry.uid)
	emit_log("Moved %s from (%d, %d) to (%d, %d)." % [get_display_name(get_unit_name_from_type(entry.type)), src.x + 1, src.y + 1, dst.x + 1, dst.y + 1])

func end_turn():
	# attempt to call global GameManager if present
	var gm = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("switch_turn"):
		gm.switch_turn()
	else:
		# local fallback: clear moved_uids
		moved_uids.clear()
		armed_unit_pos = Vector2i(-1, -1)
		emit_log("Turn ended (local). Movement reset.")

func get_unit_name_from_type(unit: UnitType) -> String:
	for unit_name in UNIT_ORDER:
		if UnitType[unit_name] == unit:
			return unit_name
	return "UNKNOWN"

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
