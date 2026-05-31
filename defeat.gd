extends Node2D

@onready var try_again_button: Button = $CanvasLayer/Control/CenterContainer/Panel/VBoxContainer/TryAgainButton
@onready var main_menu_button: Button = $CanvasLayer/Control/CenterContainer/Panel/VBoxContainer/MainMenuButton

func _ready() -> void:
	if not try_again_button.pressed.is_connected(_on_try_again_pressed):
		try_again_button.pressed.connect(_on_try_again_pressed)
	if not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
		main_menu_button.pressed.connect(_on_main_menu_pressed)

func _on_try_again_pressed() -> void:
	audiomanager.play_click_sfx()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_screen.tscn")

func _on_main_menu_pressed() -> void:
	audiomanager.play_click_sfx()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")
