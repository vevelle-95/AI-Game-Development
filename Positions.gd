extends Node
class_name Positions

# Pre-existing AI starting position presets for Monte Carlo selection.
# Each preset is an array of {"pos": Vector2, "type": String} entries.
# This allows duplicate ranks like 2 SPYs and many PRIVATES.
var ai_start_positions = [
    [
        {"pos": Vector2(0, 0), "type": "FLAG"},
        {"pos": Vector2(1, 0), "type": "FIVE_STAR"},
        {"pos": Vector2(2, 0), "type": "FOUR_STAR"},
        {"pos": Vector2(3, 0), "type": "THREE_STAR"},
        {"pos": Vector2(4, 0), "type": "COLONEL"},
        {"pos": Vector2(5, 0), "type": "MAJOR"},
        {"pos": Vector2(6, 0), "type": "LIEUTENANT"},
        {"pos": Vector2(7, 0), "type": "SERGEANT"},
        {"pos": Vector2(8, 0), "type": "SPY"},
        {"pos": Vector2(9, 0), "type": "SPY"},
        {"pos": Vector2(0, 1), "type": "TRAPO"},
        {"pos": Vector2(1, 1), "type": "PRIVATE"},
        {"pos": Vector2(2, 1), "type": "PRIVATE"},
        {"pos": Vector2(3, 1), "type": "PRIVATE"},
        {"pos": Vector2(4, 1), "type": "PRIVATE"},
        {"pos": Vector2(5, 1), "type": "PRIVATE"},
        {"pos": Vector2(6, 1), "type": "PRIVATE"},
        {"pos": Vector2(7, 1), "type": "PRIVATE"}
    ]
]
