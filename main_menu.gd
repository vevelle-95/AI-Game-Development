extends Control

const SETTINGS_SCENE := preload("res://settings.tscn")
const QUIT_SCENE := preload("res://quit.tscn")
var settings_overlay: Control = null
var quit_overlay: Control = null

func _ready():
	call_deferred("_connect_buttons")

func _connect_buttons():
	var play_btn = _find_button_by_name_or_text(self , "play", "Play Game")
	if play_btn:
		play_btn.pressed.connect(_on_PlayButton_pressed)

	var settings_btn = _find_button_by_name_or_text(self , "settings", "Settings")
	if settings_btn:
		settings_btn.pressed.connect(_on_SettingsButton_pressed)

	var quit_btn = _find_button_by_name_or_text(self , "quit", "Quit")
	if quit_btn:
		quit_btn.pressed.connect(_on_QuitButton_pressed)

func _find_button_by_name_or_text(node, keyword: String, text_match: String):
	if node is Button:
		if node.name.to_lower().find(keyword) != -1:
			return node

		if node.text == text_match:
			return node

	for child in node.get_children():
		var found = _find_button_by_name_or_text(child, keyword, text_match)

		if found:
			return found

	return null

func _on_PlayButton_pressed():
	audiomanager.play_click_sfx()
	get_tree().change_scene_to_file(
		"res://main_screen.tscn"
	)

func _on_SettingsButton_pressed():
	audiomanager.play_click_sfx()
	if settings_overlay != null:
		return

	settings_overlay = SETTINGS_SCENE.instantiate()
	settings_overlay.set_meta("opened_as_overlay", true)
	add_child(settings_overlay)

func _on_settings_closed():
	settings_overlay = null

func _on_quit_closed():
	quit_overlay = null

func _on_QuitButton_pressed():
	audiomanager.play_click_sfx()
	if quit_overlay != null:
		return

	quit_overlay = QUIT_SCENE.instantiate()
	quit_overlay.set_meta("opened_as_overlay", true)
	quit_overlay.set_meta("confirm_action", "quit_app")
	add_child(quit_overlay)
