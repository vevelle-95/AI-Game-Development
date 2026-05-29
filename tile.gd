extends Button

@onready var unit_sprite = $UnitSprite
@onready var fog_sprite = $FogSprite
@onready var fog_overlay = $FogOverlay

var grid_pos := Vector2i()
var is_selected := false
var fog_visible := false

signal tile_clicked(pos: Vector2i)

func setup(pos: Vector2i, show_fog: bool = false):
	grid_pos = pos
	fog_visible = show_fog
	if fog_sprite != null:
		fog_sprite.texture = load("res://assets/Fog.png")
	_update_fog_visibility()
	apply_color()
	
func _ready():
	pressed.connect(_on_pressed)
	if fog_sprite != null:
		fog_sprite.texture = load("res://assets/Fog.png")
	_update_fog_visibility()

func _on_pressed():
	emit_signal("tile_clicked", grid_pos)

func set_selected(selected: bool):
	is_selected = selected
	apply_color()
	
func apply_color():
	var style = StyleBoxFlat.new()

	# HALF BOARD SPLIT
	if grid_pos.y < 4: # top half (adjust if 8 rows)
		style.bg_color = Color(0.2, 0.2, 0.2) # dark side
	else:
		style.bg_color = Color(0.95, 0.95, 0.95) # white side

	# borders
	var border_width := 3 if is_selected else 1
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = Color(0.25, 0.8, 1.0) if is_selected else Color.BLACK

	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)

func set_unit(texture_path: String):
	if texture_path == "" or texture_path == null:
		unit_sprite.texture = null
		unit_sprite.visible = false
		return
	unit_sprite.texture = load(texture_path)
	unit_sprite.visible = not fog_visible

func set_fog_visible(visible: bool):
	fog_visible = visible
	_update_fog_visibility()

func _update_fog_visibility():
	if unit_sprite != null:
		unit_sprite.visible = not fog_visible and unit_sprite.texture != null
	if fog_sprite != null:
		fog_sprite.visible = fog_visible
	if fog_overlay != null:
		fog_overlay.visible = fog_visible
