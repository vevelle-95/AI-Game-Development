extends Control

const MAIN_MENU_SCENE := "res://main_menu.tscn"

@onready var prompt_label = $CenterContainer/Panel/MarginContainer/VBoxContainer/PromptLabel
@onready var confirm_button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/CancelButton

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if has_meta("opened_from_pause") and bool(get_meta("opened_from_pause")):
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	call_deferred("_connect_buttons")
	call_deferred("_refresh_copy")

func _connect_buttons():
	if confirm_button != null and not confirm_button.pressed.is_connected(_on_confirm_pressed):
		confirm_button.pressed.connect(_on_confirm_pressed)

	if cancel_button != null and not cancel_button.pressed.is_connected(_on_cancel_pressed):
		cancel_button.pressed.connect(_on_cancel_pressed)

func _get_confirm_action() -> String:
	if has_meta("confirm_action"):
		return str(get_meta("confirm_action"))
	return "quit_app"

func _refresh_copy():
	var confirm_action := _get_confirm_action()
	if prompt_label != null:
		if confirm_action == "main_menu":
			prompt_label.text = "Return to main menu?"
		else:
			prompt_label.text = "Quit the game?"

	if confirm_button != null:
		if confirm_action == "main_menu":
			confirm_button.text = "Return"
		else:
			confirm_button.text = "Quit"

func _close_overlay():
	var parent_node = get_parent()
	queue_free()
	if parent_node != null and parent_node.has_method("_on_quit_closed"):
		parent_node.call_deferred("_on_quit_closed")

func _on_confirm_pressed():
	audiomanager.play_click_sfx()
	var confirm_action := _get_confirm_action()
	if confirm_action == "main_menu":
		get_tree().paused = false
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return

	get_tree().quit()

func _on_cancel_pressed():
	audiomanager.play_click_sfx()
	_close_overlay()