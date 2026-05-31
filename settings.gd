extends Control

@onready var music_slider = $VBoxContainer/MusicSlider
@onready var sfx_slider = $VBoxContainer/SFXSlider
@onready var back_button = $VBoxContainer/BackButton

func _ready():

	music_slider.value = audiomanager.music_volume

	sfx_slider.value = audiomanager.sfx_volume

func _on_music_slider_value_changed(value):

	audiomanager.set_music_volume(value)

func _on_sfx_slider_value_changed(value):

	audiomanager.set_sfx_volume(value)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://main_menu.tscn")
