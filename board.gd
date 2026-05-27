extends Control

@export var tile_scene: PackedScene
@export var columns := 9
@export var rows := 8

@onready var grid = $"CenterContainer/Grid"

var selected_tile := Vector2i(-1, -1)
var tile_map := {}

func _ready():
	create_board()

func create_board():
	for y in rows:
		for x in columns:
			var tile = tile_scene.instantiate()
			grid.add_child(tile)
			tile.setup(Vector2i(x, y))
			
			tile.tile_clicked.connect(_on_tile_clicked)

			tile_map[Vector2i(x, y)] = tile

func _process(_delta):
	var available_size = size
	if available_size.x <= 0 or available_size.y <= 0:
		return

	var tile_size = int(floor(min(available_size.x / columns, available_size.y / rows)))
	tile_size = max(tile_size, 1)

	for child in grid.get_children():
		child.custom_minimum_size = Vector2(tile_size, tile_size)

	grid.custom_minimum_size = Vector2(tile_size * columns, tile_size * rows)
	
func _on_tile_clicked(pos: Vector2i):
	selected_tile = pos
	print("Selected:", pos)

	highlight_tiles()

func highlight_tiles():
	for tile in tile_map.values():
		tile.modulate = Color.WHITE

	if tile_map.has(selected_tile):
		tile_map[selected_tile].modulate = Color.YELLOW
