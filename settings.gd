extends Control

@onready var music_slider = $CenterContainer/Panel/MarginContainer/VBoxContainer/MusicSlider
@onready var sfx_slider = $CenterContainer/Panel/MarginContainer/VBoxContainer/SFXSlider
@onready var back_button = $CenterContainer/Panel/MarginContainer/VBoxContainer/BackButton

func _ready():
	# Wire signals in code so this scene still works even if .tscn signal links are missing.
	if music_slider != null and not music_slider.value_changed.is_connected(_on_music_slider_value_changed):
		music_slider.value_changed.connect(_on_music_slider_value_changed)

	if sfx_slider != null and not sfx_slider.value_changed.is_connected(_on_sfx_slider_value_changed):
		sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)

	if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)

	if music_slider != null:
		music_slider.value = audiomanager.music_volume

	if sfx_slider != null:
		sfx_slider.value = audiomanager.sfx_volume

func _on_music_slider_value_changed(value):
	audiomanager.set_music_volume(value)

func _on_sfx_slider_value_changed(value):
	audiomanager.set_sfx_volume(value)

func _on_back_pressed():
	audiomanager.play_click_sfx()
	var opened_as_overlay := (has_meta("opened_as_overlay") and bool(get_meta("opened_as_overlay"))) or (has_meta("opened_from_pause") and bool(get_meta("opened_from_pause")))
	if opened_as_overlay:
		var parent_node = get_parent()
		queue_free()
		if parent_node != null and parent_node.has_method("_on_settings_closed"):
			parent_node.call_deferred("_on_settings_closed")
		return

	var target_scene := audiomanager.settings_return_scene
	if target_scene == "":
		target_scene = "res://main_menu.tscn"
	get_tree().change_scene_to_file(target_scene)
