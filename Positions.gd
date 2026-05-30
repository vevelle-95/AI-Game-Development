extends Node
class_name Positions

func randomize_ai_positions() -> Array:
    # Randomly select one of the predefined AI starting position presets
    var presets = [ai_start_positions1, ai_start_positions2, ai_start_positions3]
    return presets.pick_random()
    
# Pre-existing AI starting position presets for Monte Carlo selection.
# Each preset is an array of {"pos": Vector2i, "type": String} entries.
# Coordinates use column/row ordering: Vector2i(column, row).
# Column is left-to-right (0..9), row is top-to-bottom (0..9).
var ai_start_positions1 = [
	[
		# --- Row 0 (Backline Formations) ---
		{"pos": Vector2i(0, 0), "type": "SPY"},
		{"pos": Vector2i(1, 0), "type": "PRIVATE"},
		{"pos": Vector2i(2, 0), "type": "SERGEANT"},
		{"pos": Vector2i(3, 0), "type": "THREE_STAR"},
		{"pos": Vector2i(4, 0), "type": "FIVE_STAR"},
		{"pos": Vector2i(5, 0), "type": "FLAG"}, # Safe back-center position
		{"pos": Vector2i(6, 0), "type": "FOUR_STAR"},
		{"pos": Vector2i(7, 0), "type": "COLONEL"},
		{"pos": Vector2i(8, 0), "type": "PRIVATE"},
		{"pos": Vector2i(9, 0), "type": "SPY"},

		# --- Row 1 (Midline Formations) ---
		{"pos": Vector2i(0, 1), "type": "TRAPO"},
		{"pos": Vector2i(1, 1), "type": "PRIVATE"},
		{"pos": Vector2i(2, 1), "type": "MAJOR"},
		{"pos": Vector2i(3, 1), "type": "LIEUTENANT"},
		{"pos": Vector2i(4, 1), "type": "PRIVATE"},
		{"pos": Vector2i(5, 1), "type": "PRIVATE"},
		{"pos": Vector2i(6, 1), "type": "PRIVATE"},
		{"pos": Vector2i(7, 1), "type": "PRIVATE"}
	]
]

var ai_start_positions2 = [
	[
		# Row 0
		{"pos": Vector2i(0, 0), "type": "SPY"},
		{"pos": Vector2i(1, 0), "type": "PRIVATE"},
		{"pos": Vector2i(2, 0), "type": "SERGEANT"},
		{"pos": Vector2i(3, 0), "type": "THREE_STAR"},
		{"pos": Vector2i(5, 0), "type": "FLAG"}, # Safe back-center position
		{"pos": Vector2i(6, 0), "type": "FOUR_STAR"},
		{"pos": Vector2i(7, 0), "type": "COLONEL"},
		{"pos": Vector2i(8, 0), "type": "PRIVATE"},
		{"pos": Vector2i(9, 0), "type": "SPY"},

		# Row 1 (Midline Formations)
		{"pos": Vector2i(0, 1), "type": "TRAPO"},
		{"pos": Vector2i(1, 1), "type": "PRIVATE"},
		{"pos": Vector2i(2, 1), "type": "MAJOR"},
		{"pos": Vector2i(3, 1), "type": "LIEUTENANT"},
		{"pos": Vector2i(4, 1), "type": "PRIVATE"},
		{"pos": Vector2i(6, 1), "type": "PRIVATE"},

        #row 2: (Fodder Line with hidden high-value targets)
        {"pos": Vector2i(3, 2), "type": "PRIVATE"},
        {"pos": Vector2i(4, 2), "type": "FIVE_STAR"},
        {"pos": Vector2i(5, 2), "type": "PRIVATE"},
        {"pos": Vector2i(6, 2), "type": "SPY"},

	]
]

var ai_start_positions3 = [
    [
        # Row 0
        {"pos": Vector2i(0, 0), "type": "SPY"},
        {"pos": Vector2i(1, 0), "type": "PRIVATE"},
        {"pos": Vector2i(2, 0), "type": "SERGEANT"},
        {"pos": Vector2i(3, 0), "type": "THREE_STAR"},
        {"pos": Vector2i(4, 0), "type": "FIVE_STAR"},
        {"pos": Vector2i(5, 0), "type": "FLAG"}, # Safe back-center position
        {"pos": Vector2i(6, 0), "type": "FOUR_STAR"},
        {"pos": Vector2i(7, 0), "type": "COLONEL"},
        {"pos": Vector2i(9, 0), "type": "SPY"},

        # Row 1 (Midline Formations)
        {"pos": Vector2i(0, 1), "type": "TRAPO"},
        {"pos": Vector2i(1, 1), "type": "PRIVATE"},
        {"pos": Vector2i(2, 1), "type": "MAJOR"},
        {"pos": Vector2i(3, 1), "type": "LIEUTENANT"},
        {"pos": Vector2i(4, 1), "type": "PRIVATE"},
        #Row 3 remaining positions are empty to create a more defense
        {"pos": Vector2i(5, 1), "type": "PRIVATE"},
        {"pos": Vector2i(6, 1), "type": "PRIVATE"},
        {"pos": Vector2i(7, 1), "type": "PRIVATE"},
        {"pos": Vector2i(8, 1), "type": "PRIVATE"}
    ]
]


