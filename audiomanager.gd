extends Node

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var music_volume := 50.0
var sfx_volume := 50.0
var settings_return_scene := "res://main_menu.tscn"

const MOVE_SFX := preload("res://assets/sfx/movement.mp3")
const CLICK_SFX := preload("res://assets/sfx/click.mp3")
const TILE_SELECT_SFX := preload("res://assets/sfx/tile-select.mp3")

var _move_sfx_player: AudioStreamPlayer = null
var _click_sfx_player: AudioStreamPlayer = null
var _tile_select_sfx_player: AudioStreamPlayer = null

func set_settings_return_scene(scene_path: String):
	settings_return_scene = scene_path

func _ensure_bus_exists(bus_name: String) -> int:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		return bus_index

	AudioServer.add_bus()
	bus_index = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	return bus_index

func _volume_to_db(value: float) -> float:
	if value <= 0.0:
		return -80.0
	return linear_to_db(value / 100.0)

func set_music_volume(value):
	music_volume = clampf(value, 0.0, 100.0)
	var music_bus_index := _ensure_bus_exists(MUSIC_BUS)

	AudioServer.set_bus_volume_db(music_bus_index, _volume_to_db(music_volume))

func set_sfx_volume(value):
	sfx_volume = clampf(value, 0.0, 100.0)
	var sfx_bus_index := _ensure_bus_exists(SFX_BUS)

	AudioServer.set_bus_volume_db(sfx_bus_index, _volume_to_db(sfx_volume))

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus_exists(MUSIC_BUS)
	_ensure_bus_exists(SFX_BUS)
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)

	_move_sfx_player = AudioStreamPlayer.new()
	_move_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_move_sfx_player.bus = SFX_BUS
	_move_sfx_player.stream = MOVE_SFX
	add_child(_move_sfx_player)

	_click_sfx_player = AudioStreamPlayer.new()
	_click_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_click_sfx_player.bus = SFX_BUS
	_click_sfx_player.stream = CLICK_SFX
	add_child(_click_sfx_player)

	_tile_select_sfx_player = AudioStreamPlayer.new()
	_tile_select_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_tile_select_sfx_player.bus = SFX_BUS
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
