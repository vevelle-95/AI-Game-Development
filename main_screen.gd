extends Node2D

@onready var board = $"UI/VBoxContainer/MiddleArea/BoardPanel/BoardRoot"
@onready var top_phase_label = $"UI/VBoxContainer/TopBar/Player Turn"
@onready var bounty_label = $"UI/VBoxContainer/TopBar/Credits"
@onready var turn_label = $"UI/VBoxContainer/TopBar/Turn #"
@onready var ready_button = $"UI/VBoxContainer/TopBar/Button"
@onready var selected_unit_label = $"UI/VBoxContainer/MiddleArea/RightPanel/Selected Unit"
@onready var unit_picker = $"UI/VBoxContainer/MiddleArea/RightPanel/UnitPicker"
@onready var stats_label: RichTextLabel = $"UI/VBoxContainer/MiddleArea/RightPanel/Stats"
@onready var log_label: RichTextLabel = $"UI/VBoxContainer/MiddleArea/RightPanel/LogPanel/LogVBox/LogScroll/Log"

const MAX_LOG_LINES := 300
var log_lines: Array[String] = []

const UNIT_MATCHUP_DETAILS := {
	"FLAG": {"strong": "None", "weak": "All enemy units"},
	"FIVE_STAR": {"strong": "All lower officers", "weak": "Spy"},
	"FOUR_STAR": {"strong": "Three-Star Fenerals and lower officers", "weak": "Five-Star, Spy"},
	"THREE_STAR": {"strong": "Colonel and below", "weak": "Higher generals, Spy"},
	"COLONEL": {"strong": "Major, Lieutenant, Sergeant, Private", "weak": "Generals, Spy"},
	"MAJOR": {"strong": "Lieutenant, Sergeant, Private", "weak": "Colonel and above, Spy"},
	"LIEUTENANT": {"strong": "Sergeant, Private", "weak": "Major and above, Spy"},
	"SERGEANT": {"strong": "Private", "weak": "Lieutenant and above, Spy"},
	"SPY": {"strong": "Five-Star General and lower officers", "weak": "Private"},
	"PRIVATE": {"strong": "Spy", "weak": "Sergeant and above"}
}

const TRAPO_SPECIAL_TEXT := "Trapo Unit (Special Ability System)\nThe Trapo unit has a unique ability called Corrupt, which allows temporary control of enemy units using in-game currency.\n\nAbility: Corrupt\nCan target any enemy unit except the Flag\nControlled unit duration: 2 turns\nControlled units cannot capture the Flag\nControlled units cannot use special abilities\n\nCost System:\nPrivate: Low cost\nSergeant-Lieutenant: Medium cost\nMajor-Colonel: High cost\nGenerals: Very high cost\n\nRestrictions:\nAbility range: Must be within 2 tiles\nCooldown: 3-5 turns after use\nCannot repeatedly target the same unit consecutively\n\nThis system introduces strategic resource management and decision-making."

func _ready():
	setup_unit_picker()
	setup_game_log()
	reset_stats()
	setup_ready_button()
	board.log_message.connect(_on_board_log_message)
	board.selected_tile_unit_info.connect(_on_selected_tile_unit_info)
	board.phase_changed.connect(_on_board_phase_changed)
	board.turn_changed.connect(_on_board_turn_changed)
	board.bounty_changed.connect(_on_board_bounty_changed)
	top_phase_label.text = board.get_current_turn_name()
	_update_bounty_label(0, 0, "")
	turn_label.text = "TURN %d" % board.get_turn_number()


func setup_unit_picker():
	unit_picker.clear()

	for unit_name in board.get_unit_names():
		unit_picker.add_item(format_unit_name(unit_name))

	var selected_name = board.get_selected_unit_name()
	var selected_index = board.get_unit_names().find(selected_name)
	if selected_index >= 0:
		unit_picker.select(selected_index)
		update_selected_unit_label(selected_name)

	unit_picker.item_selected.connect(_on_unit_picker_item_selected)

func _on_unit_picker_item_selected(index: int):
	var unit_names = board.get_unit_names()
	if index < 0 or index >= unit_names.size():
		return

	var unit_name = unit_names[index]
	board.set_selected_unit_by_name(unit_name)
	update_selected_unit_label(unit_name)

func update_selected_unit_label(unit_name: String):
	selected_unit_label.text = "Selected Unit: %s" % format_unit_name(unit_name)

func format_unit_name(raw_name: String) -> String:
	var words = raw_name.to_lower().split("_")
	for i in words.size():
		words[i] = words[i].capitalize()
	return " ".join(words)

func setup_game_log():
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.scroll_following = true
	log_lines.clear()
	append_log("Game log online.")
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func setup_ready_button():
	ready_button.text = "READY"
	ready_button.pressed.connect(_on_ready_button_pressed)
	ready_button.disabled = false

func _on_end_turn_pressed():
	board.end_turn()
	append_log("End Turn pressed.")

func _on_ready_button_pressed():
	if board.lock_setup_phase():
		# switch button to End Turn mode
		ready_button.text = "END TURN"
		unit_picker.disabled = true
		# reconnect to end-turn handler
		ready_button.pressed.disconnect(_on_ready_button_pressed)
		ready_button.pressed.connect(_on_end_turn_pressed)

func _on_board_phase_changed(phase_name: String):
	if phase_name == "battle":
		top_phase_label.text = "BATTLE PHASE"
		append_log("Battle phase active. Placement is locked.")

func _on_board_turn_changed(turn_name: String):
	if top_phase_label.text != "BATTLE PHASE":
		top_phase_label.text = turn_name
	turn_label.text = "TURN %d" % board.get_turn_number()

func _on_board_bounty_changed(total_bounty: int, last_bounty: int, killed_unit_name: String):
	_update_bounty_label(total_bounty, last_bounty, killed_unit_name)

func _update_bounty_label(total_bounty: int, last_bounty: int, killed_unit_name: String):
	if last_bounty > 0 and killed_unit_name != "":
		bounty_label.text = "CREDITS: %d  (+%d %s)" % [total_bounty, last_bounty, format_unit_name(killed_unit_name)]
	else:
		bounty_label.text = "CREDITS: %d" % total_bounty

func _on_board_log_message(message: String):
	append_log(message)

func append_log(message: String):
	var stamp = Time.get_time_string_from_system()
	var line = "> [%s] %s" % [stamp, message]
	log_lines.append(line)

	if log_lines.size() > MAX_LOG_LINES:
		log_lines = log_lines.slice(log_lines.size() - MAX_LOG_LINES, log_lines.size())

	log_label.text = "\n".join(log_lines)
	log_label.scroll_to_line(max(log_label.get_line_count() - 1, 0))

func _on_selected_tile_unit_info(unit_name: String, rank: String, vision: String, movement: String):
	if unit_name == "":
		reset_stats()
		return

	if unit_name == "TRAPO":
		stats_label.text = "Rank: %s\nVision: %s\nMovement: %s\n\n%s" % [rank, vision, movement, TRAPO_SPECIAL_TEXT]
		return

	var matchup = UNIT_MATCHUP_DETAILS.get(unit_name, {"strong": "Unknown", "weak": "Unknown"})
	stats_label.text = "Rank: %s\nVision: %s\nMovement: %s\n\nStrong Against: %s\nWeak Against: %s" % [rank, vision, movement, matchup["strong"], matchup["weak"]]

func reset_stats():
	stats_label.text = "Rank: \nVision: \nMovement: \n\nStrong Against: \nWeak Against: "
