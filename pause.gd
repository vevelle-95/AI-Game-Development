extends Control

const SETTINGS_SCENE := preload("res://settings.tscn")
var settings_overlay: Control = null

func _ready():
	visible = false

func pause_game():
	visible = true
	get_tree().paused = true

func resume_game():
	visible = false
	get_tree().paused = false

func _on_resume_button_pressed():
	audiomanager.play_click_sfx()
	visible = false
	get_tree().paused = false

func _on_restart_button_pressed():
	audiomanager.play_click_sfx()
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_menu_button_pressed():
	audiomanager.play_click_sfx()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_settings_button_pressed():
	audiomanager.play_click_sfx()
	if settings_overlay != null:
		return

	settings_overlay = SETTINGS_SCENE.instantiate()
	settings_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	settings_overlay.set_meta("opened_as_overlay", true)
	settings_overlay.set_meta("opened_from_pause", true)
	add_child(settings_overlay)
	$CenterContainer.visible = false

func _on_settings_closed():
	settings_overlay = null
	$CenterContainer.visible = true
	visible = true
	get_tree().paused = true
	
func _on_return_button_pressed():
	visible = false
	get_tree().paused = false
