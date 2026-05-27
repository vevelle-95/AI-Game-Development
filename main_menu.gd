extends Control

func _ready():
	# Defer connection until after the scene is fully instantiated
	call_deferred("_connect_play_button")

func _connect_play_button():
	var btn = get_node_or_null("Center/VBox/PlayButton")
	if not btn:
		btn = _find_play_button(self )
	if btn:
		btn.connect("pressed", Callable(self , "_on_PlayButton_pressed"))
		print("MainMenu: connected to Play button ('%s')" % btn.name)
	else:
		var child_names = []
		for c in get_children():
			child_names.append(c.name)
		push_error("MainMenu: PlayButton not found at Center/VBox/PlayButton. Root children: %s" % child_names)

func _find_play_button(node):
	if node is Button:
		# prefer nodes named PlayButton or with text "Play Game"
		if node.name.to_lower().find("play") != -1 or node.text == "Play Game":
			return node
		# otherwise, return the first Button found
		return node
	for child in node.get_children():
		var found = _find_play_button(child)
		if found:
			return found
	return null

func _on_PlayButton_pressed():
	# Robust scene change: prefer change_scene_to(PackedScene), then change_scene_to_file(), then change_scene()
	var path = "res://main_screen.tscn"
	var scene_res = null
	# try loading the PackedScene first
	if ResourceLoader.has_cached(path):
		scene_res = ResourceLoader.load(path)
	else:
		scene_res = ResourceLoader.load(path)

	if scene_res and get_tree().has_method("change_scene_to"):
		get_tree().change_scene_to(scene_res)
		return
	if get_tree().has_method("change_scene_to_file"):
		get_tree().change_scene_to_file(path)
		return
	if get_tree().has_method("change_scene"):
		get_tree().change_scene(path)
		return
	push_error("MainMenu: no compatible SceneTree method found to change scene to %s" % path)
