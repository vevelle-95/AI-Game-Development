extends Node

var music_volume := 50
var sfx_volume := 50

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
