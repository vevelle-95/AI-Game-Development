extends Button

var grid_pos := Vector2i()

signal tile_clicked(pos: Vector2i)

func setup(pos: Vector2i):
	grid_pos = pos
	apply_color()
	
func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	emit_signal("tile_clicked", grid_pos)
	
func apply_color():
	var style = StyleBoxFlat.new()

	# HALF BOARD SPLIT
	if grid_pos.y < 4:  # top half (adjust if 8 rows)
		style.bg_color = Color(0.95, 0.95, 0.95)  # white side
	else:
		style.bg_color = Color(0.2, 0.2, 0.2)  # dark side

	# borders
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color.BLACK

	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
