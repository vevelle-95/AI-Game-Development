extends Button

@onready var unit_sprite = $UnitSprite

var grid_pos := Vector2i()
var is_selected := false

signal tile_clicked(pos: Vector2i)

func setup(pos: Vector2i):
	grid_pos = pos
	apply_color()
	
func _ready():
	pressed.connect(_on_pressed)

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
	unit_sprite.texture = load(texture_path)
