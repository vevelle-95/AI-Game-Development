extends Control

func _ready():
	visible = false

func pause_game():

	visible = true

	get_tree().paused = true

func resume_game():

	visible = false

	get_tree().paused = false

func _on_resume_button_pressed():

	resume_game()

func _on_restart_button_pressed():

	get_tree().paused = false

	get_tree().reload_current_scene()

func _on_settings_button_pressed():

	get_tree().paused = false

	get_tree().change_scene_to_file(
		"res://settings.tscn"
	)

func _on_menu_button_pressed():

	get_tree().paused = false

	get_tree().change_scene_to_file(
		"res://main_menu.tscn"
	)
