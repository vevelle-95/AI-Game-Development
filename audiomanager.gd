extends Node

var music_volume := 50
var sfx_volume := 50
var settings_return_scene := "res://main_menu.tscn"

const MOVE_SFX := preload("res://assets/sfx/movement.mp3")
const CLICK_SFX := preload("res://assets/sfx/click.mp3")
const TILE_SELECT_SFX := preload("res://assets/sfx/tile-select.mp3")

var _move_sfx_player: AudioStreamPlayer = null
var _click_sfx_player: AudioStreamPlayer = null
var _tile_select_sfx_player: AudioStreamPlayer = null

func set_settings_return_scene(scene_path: String):
	settings_return_scene = scene_path

func set_music_volume(value):
	music_volume = value

	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Music"),
		linear_to_db(value / 100.0)
	)

func set_sfx_volume(value):
	sfx_volume = value

	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("SFX"),
		linear_to_db(value / 100.0)
	)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	_move_sfx_player = AudioStreamPlayer.new()
	_move_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_move_sfx_player.bus = "SFX"
	_move_sfx_player.stream = MOVE_SFX
	add_child(_move_sfx_player)

	_click_sfx_player = AudioStreamPlayer.new()
	_click_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_click_sfx_player.bus = "SFX"
	_click_sfx_player.stream = CLICK_SFX
	add_child(_click_sfx_player)

	_tile_select_sfx_player = AudioStreamPlayer.new()
	_tile_select_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_tile_select_sfx_player.bus = "SFX"
	_tile_select_sfx_player.stream = TILE_SELECT_SFX
	add_child(_tile_select_sfx_player)

func play_move_sfx() -> void:
	if _move_sfx_player == null:
		return
	_move_sfx_player.stop()
	_move_sfx_player.play()

func play_click_sfx() -> void:
	if _click_sfx_player == null:
		return
	_click_sfx_player.stop()
	_click_sfx_player.play()

func play_tile_select_sfx() -> void:
	if _tile_select_sfx_player == null:
		return
	_tile_select_sfx_player.stop()
	_tile_select_sfx_player.play()
