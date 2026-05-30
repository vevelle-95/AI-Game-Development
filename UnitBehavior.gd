extends Node
class_name UnitBehavior

# MOVEMENT RULES

func can_move(rank: GameConstants.Rank) -> bool:
	return true

func get_move_range(rank: GameConstants.Rank) -> int:
	return 1

# VISION RULES

func get_vision_range(rank: GameConstants.Rank) -> int:
	return GameConstants.get_vision_range(rank)

func has_diagonal_vision(rank: GameConstants.Rank) -> bool:
	return rank in [
		GameConstants.Rank.GENERAL_3,
		GameConstants.Rank.GENERAL_4,
		GameConstants.Rank.GENERAL_5
	]

# Unit Type Helpers

func is_general(rank: GameConstants.Rank) -> bool:
	return rank in [
		GameConstants.Rank.GENERAL_3,
		GameConstants.Rank.GENERAL_4,
		GameConstants.Rank.GENERAL_5
	]

func is_spy(rank: GameConstants.Rank) -> bool:
	return rank == GameConstants.Rank.SPY

func is_trapo(rank: GameConstants.Rank) -> bool:
	return rank == GameConstants.Rank.TRAPO

func is_flag(rank: GameConstants.Rank) -> bool:
	return rank == GameConstants.Rank.FLAG

# Special Combat Rules

#spy can defeat generals ONLY when attacking
func spy_can_defeat(attacker_rank = GameConstants.Rank, defender_rank = GameConstants.Rank) -> bool:
	if attacker_rank == GameConstants.Rank.SPY:
		if is_general(defender_rank):
			return true
	return false

func private_can_defeat_spy(attacker_rank = GameConstants.Rank, defender_rank = GameConstants.Rank) -> bool:
	return (
		attacker_rank == GameConstants.Rank.PRIVATE and defender_rank == GameConstants.Rank.SPY
	)

func trapo_loses_combat(rank: GameConstants.Rank) -> bool:
	return rank == GameConstants.Rank.TRAPO

# Bounty System

func get_bounty(rank: GameConstants.Rank) -> int:
	if GameConstants.BOUNTIES.has(rank):
		return GameConstants.BOUNTIES[rank]
	return 0

func get_catchup_bonus(original_reward: int) -> int:
	return int(original_reward * 0.2)

#Trapo Corruption System

const CORRUPT_DURATION = 2
const CORRUPT_RANGE = 2
const CORRUPT_COOLDOWN = 3

func can_corrupt(
	trapo_position: Vector2i,
	target_position: Vector2i,
	target_rank: GameConstants.Rank
) -> bool:
	if target_rank == GameConstants.Rank.FLAG:
		return false

	var distance = trapo_position.distance_to(target_position)

	if distance > CORRUPT_RANGE:
		return false
	return true

func get_corrupt_cost(rank: GameConstants.Rank) -> int:
	match rank:
		GameConstants.Rank.PRIVATE:
			return 25
		GameConstants.Rank.SERGEANT, GameConstants.Rank.LIEUTENANT:
			return 50
		GameConstants.Rank.MAJOR, GameConstants.Rank.COLONEL:
			return 75
		GameConstants.Rank.GENERAL_3, GameConstants.Rank.GENERAL_4, GameConstants.Rank.GENERAL_5:
			return 120
		GameConstants.Rank.SPY:
			return 60
		GameConstants.Rank.TRAPO:
			return 100
		_:
			return 999

func corrupted_unit_can_capture_flag() -> bool:
	return false

func corrupted_unit_can_use_abilities() -> bool:
	return false

#fog of war helpers

func is_enemy_visible(
	observer_position: Vector2i,
	target_position: Vector2i,
	observer_rank: GameConstants.Rank
) -> bool:

	var vision_range = get_vision_range(observer_rank)

	var dx = abs(target_position.x - observer_position.x)
	var dy = abs(target_position.y - observer_position.y)

	# Same column
	if dx == 0 and dy <= vision_range:
		return true

	# Same row
	if dy == 0 and dx <= vision_range:
		return true

	return false

#AI / Strategic Helpers
func is_high_value(rank: GameConstants.Rank) -> bool:
	return rank in [
		GameConstants.Rank.COLONEL,
		GameConstants.Rank.GENERAL_3,
		GameConstants.Rank.GENERAL_4,
		GameConstants.Rank.GENERAL_5
	]

func get_rank_name(rank: GameConstants.Rank) -> String:
	match rank:
		GameConstants.Rank.FLAG:
			return "Flag"
		GameConstants.Rank.SPY:
			return "Spy"
		GameConstants.Rank.PRIVATE:
			return "Private"
		GameConstants.Rank.SERGEANT:
			return "Sergeant"
		GameConstants.Rank.LIEUTENANT:
			return "Lieutenant"
		GameConstants.Rank.COLONEL:
			return "Colonel"
		GameConstants.Rank.MAJOR:
			return "Major"
		GameConstants.Rank.GENERAL_3:
			return "3-Star General"
		GameConstants.Rank.GENERAL_4:
			return "4-Star General"
		GameConstants.Rank.GENERAL_5:
			return "5-Star General"
		GameConstants.Rank.TRAPO:
			return "Trapo"
		_:
			return "Unknown"
