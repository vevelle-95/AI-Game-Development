extends Node2D

const VICTORY_SCENE := preload("res://victory.tscn")
const DEFEAT_SCENE := preload("res://defeat.tscn")

@onready var board = $"UI/VBoxContainer/MiddleArea/BoardPanel/BoardRoot"
@onready var top_phase_label = $"UI/VBoxContainer/TopBar/Player Turn"
@onready var bounty_label = $"UI/VBoxContainer/TopBar/Credits"
@onready var turn_label = $"UI/VBoxContainer/TopBar/Turn #"
@onready var ready_button = $"UI/VBoxContainer/TopBar/Button"
@onready var bribe_button = $"UI/VBoxContainer/MiddleArea/RightPanel/BribeButton"
@onready var selected_unit_label = $"UI/VBoxContainer/MiddleArea/RightPanel/Selected Unit"
@onready var unit_picker = $"UI/VBoxContainer/MiddleArea/RightPanel/UnitPicker"
@onready var enemy_units_label = $"UI/VBoxContainer/MiddleArea/RightPanel/EnemyUnits"
@onready var stats_label: RichTextLabel = $"UI/VBoxContainer/MiddleArea/RightPanel/Stats"
@onready var log_label: RichTextLabel = $"UI/VBoxContainer/MiddleArea/RightPanel/LogPanel/LogScroll/Log"
@onready var p1_timer_label: Label = $"UI/VBoxContainer/TopBar/Player Timer"
@onready var ai_timer_label: Label = $"UI/VBoxContainer/TopBar/AI Timer"
@onready var pause_menu = $"UI/PauseMenu"
@onready var pause_button = $"UI/VBoxContainer/TopBar/PauseButton"

const MAX_LOG_LINES := 300
var log_lines: Array[String] = []
var _result_screen_shown := false
var _result_overlay: Node = null

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

const TRAPO_SPECIAL_TEXT := "Trapo Unit (Bribe System)\nThe Trapo unit can bribe an enemy unit to reveal its identity through fog of war.\n\nAbility: Bribe\nTarget any enemy unit except the Flag\nReveal duration: Permanent until the tile changes\nBribe cost is based on the target's bounty\n\nRestrictions:\nAbility range: Must be within 2 tiles\nRequires enough credits in the Trapo wallet\nWorks only on your turn\n\nThis gives the Trapo a vision-focused support skill instead of a combat ability."

func _ready():
	setup_unit_picker()
	setup_game_log()
	reset_stats()
	setup_ready_button()
	setup_bribe_button()
	board.log_message.connect(_on_board_log_message)
	board.selected_tile_unit_info.connect(_on_selected_tile_unit_info)
	board.phase_changed.connect(_on_board_phase_changed)
	board.turn_changed.connect(_on_board_turn_changed)
	board.bounty_changed.connect(_on_board_bounty_changed)
	board.enemy_units_changed.connect(_on_enemy_units_changed)
	top_phase_label.text = "GAME OF THE GENERALS"
	top_phase_label.add_theme_color_override("font_color", Color.WHITE)
	_update_bounty_label(0, 0)
	turn_label.text = board.get_current_turn_name()
	_apply_turn_indicator_colors(board.game_manager.get_turn_color())
	_on_enemy_units_changed(board.get_enemy_units_captured(), board.get_enemy_units_remaining())
	pause_button.pressed.connect(_on_pause_button_pressed)

func _on_pause_button_pressed():
	pause_menu.pause_game()


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

func _get_tier_label(rank: String) -> String:
	# Rank is a human string like "Colonel" or "Five-Star General"
	if rank == null or rank == "":
		return ""
	if rank.find("General") >= 0:
		return "High Tier Official"
	if rank in ["Colonel", "Major", "Lieutenant"]:
		return "Mid Tier Official"
	return "Low Tier Official"

func setup_ready_button():
	ready_button.text = "READY"
	ready_button.pressed.connect(_on_ready_button_pressed)
	ready_button.disabled = false

func setup_bribe_button():
	bribe_button.text = "BRIBE"
	bribe_button.pressed.connect(_on_bribe_button_pressed)
	bribe_button.disabled = false
	bribe_button.visible = false

func _on_end_turn_pressed():
	board.end_turn()
	append_log("End Turn pressed.")

func _on_bribe_button_pressed():
	board.start_bribe_mode()

func _on_ready_button_pressed():
	if board.lock_setup_phase():
		# switch the setup button into the in-game pause button
		ready_button.text = "PAUSE"
		unit_picker.disabled = true
		pause_button.visible = false
		ready_button.pressed.disconnect(_on_ready_button_pressed)
		ready_button.pressed.connect(_on_pause_button_pressed)

func _on_board_phase_changed(phase_name: String):
	if phase_name == "battle":
		top_phase_label.add_theme_color_override("font_color", Color.WHITE)
		append_log("Battle phase active. Placement is locked.")

func _on_board_turn_changed(turn_name: String, turn_color: Color):
	turn_label.text = turn_name
	_apply_turn_indicator_colors(turn_color)

func _apply_turn_indicator_colors(turn_color: Color):
	var inactive_color := Color(0.65, 0.65, 0.65)
	if turn_label:
		turn_label.add_theme_color_override("font_color", turn_color)
	if board and board.game_manager:
		if board.game_manager.current_turn == GameManager.PlayTurn.PLAYER1:
			p1_timer_label.add_theme_color_override("font_color", turn_color)
			ai_timer_label.add_theme_color_override("font_color", inactive_color)
		else:
			p1_timer_label.add_theme_color_override("font_color", inactive_color)
			ai_timer_label.add_theme_color_override("font_color", turn_color)

func _on_board_bounty_changed(total_bounty: int, last_bounty: int, _killed_unit_name: String):
	_update_bounty_label(total_bounty, last_bounty)

func _on_enemy_units_changed(captured: int, remaining: int):
	if enemy_units_label:
		enemy_units_label.text = "Enemy Units: %d captured / %d remaining" % [captured, remaining]

func _update_bounty_label(total_bounty: int, last_bounty: int):
	if last_bounty > 0:
		bounty_label.text = "CREDITS: %d  (+%d)" % [total_bounty, last_bounty]
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
	# FIX: get_line_count() returns a stale value immediately after setting text
	# because RichTextLabel defers its layout recompute to the next frame.
	# scroll_following = true (set in setup_game_log) handles auto-scrolling correctly,
	# so the manual scroll_to_line call is removed — it was the cause of the one-move delay.

func _on_selected_tile_unit_info(unit_name: String, rank: String, vision: String, movement: String):
	if unit_name == "":
		bribe_button.visible = false
		selected_unit_label.text = "Selected Unit: "
		reset_stats()
		return

	if unit_name == "TRAPO":
		bribe_button.visible = true
		selected_unit_label.text = "Selected Unit: %s" % format_unit_name(unit_name)
		var tier = _get_tier_label(rank)
		stats_label.text = "Rank: %s\nTier: %s\nVision: %s\nMovement: %s\n\n%s" % [rank, tier, vision, movement, TRAPO_SPECIAL_TEXT]
		return

	bribe_button.visible = false

	selected_unit_label.text = "Selected Unit: %s" % format_unit_name(unit_name)
	var tier = _get_tier_label(rank)
	var matchup = UNIT_MATCHUP_DETAILS.get(unit_name, {"strong": "Unknown", "weak": "Unknown"})
	stats_label.text = "Rank: %s\nTier: %s\nVision: %s\nMovement: %s\n\nStrong Against: %s\nWeak Against: %s" % [rank, tier, vision, movement, matchup["strong"], matchup["weak"]]

func reset_stats():
	stats_label.text = "Rank: \nVision: \nMovement: \n\nStrong Against: \nWeak Against: "

func format_time(time_in_seconds: float) -> String:
	if time_in_seconds <= 0.0:
		return "00:00"
	var minutes := int(time_in_seconds) / 60
	var seconds := int(time_in_seconds) % 60
	return "%02d:%02d" % [minutes, seconds]


func _process(delta: float) -> void:
	# Ensure the board and game manager instances exist before pulling data
	if board and board.game_manager:
		var gm = board.game_manager

		if gm.game_over and not _result_screen_shown:
			_show_game_result(gm)
			return
		
		# 1. Update Player 1 Timer UI
		if p1_timer_label:
			var p1_time = gm.p1_time_remaining
			if p1_time > 0.0:
				var p1_mins := int(p1_time) / 60
				var p1_secs := int(p1_time) % 60
				p1_timer_label.text = "P1: %02d:%02d" % [p1_mins, p1_secs]
			else:
				p1_timer_label.text = "P1: TIME'S UP!"

		# 2. Update AI Timer UI
		if ai_timer_label:
			var ai_time = gm.ai_time_remaining
			if ai_time > 0.0:
				var ai_mins := int(ai_time) / 60
				var ai_secs := int(ai_time) % 60
				ai_timer_label.text = "AI: %02d:%02d" % [ai_mins, ai_secs]
			else:
				ai_timer_label.text = "AI: TIME'S UP!"

func _show_game_result(gm: GameManager) -> void:
	_result_screen_shown = true
	var result_scene: PackedScene = VICTORY_SCENE if gm.game_result == GameManager.GameResult.PLAYER_WIN else DEFEAT_SCENE
	_result_overlay = result_scene.instantiate()
	_result_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_result_overlay)
	get_tree().paused = true
