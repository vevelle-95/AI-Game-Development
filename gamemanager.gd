extends Node
class_name GameManager

enum PlayTurn {
	PLAYER1,
	AI
}

var current_turn: PlayTurn = PlayTurn.PLAYER1
var game_over: bool = false
var trapo_wallet: int = 0 # TRAPO starts with 0 bribe money

func fog_of_war_enabled() -> bool:
	# Returns true if the fog of war is enabled, false otherwise
	return true

func switch_turn() -> void:
	if current_turn == PlayTurn.PLAYER1:
		current_turn = PlayTurn.AI
	else:
		current_turn = PlayTurn.PLAYER1

func add_kill_bounty(killed_rank: GameConstants.Rank) -> void:
	# For every kill, add the bounty of the killed piece to the TRAPO wallet
	var bounty: int = 0
	if GameConstants.BOUNTIES.has(killed_rank):
		bounty = GameConstants.BOUNTIES[killed_rank]
	print("DEBUG: GameManager.add_kill_bounty called for", killed_rank, "bounty=", bounty, "wallet_before=", trapo_wallet)
	trapo_wallet += bounty
	print("DEBUG: GameManager.trapo_wallet now=", trapo_wallet)

func check_bribe_success(enemy_rank: GameConstants.Rank) -> bool:
	# Checks if the TRAPO has enough money to bribe the enemy piece based on its rank
	var enemy_bribe: int = get_bribe_cost(enemy_rank)
	if enemy_bribe <= 0:
		return false
	return trapo_wallet >= enemy_bribe

func get_bribe_cost(enemy_rank: GameConstants.Rank) -> int:
	if enemy_rank == GameConstants.Rank.FLAG:
		return 0
	return GameConstants.BOUNTIES.get(enemy_rank, 0)

func can_bribe_enemy(enemy_rank: GameConstants.Rank) -> bool:
	return check_bribe_success(enemy_rank)

func bribe_enemy(enemy_rank: GameConstants.Rank) -> bool:
	if not can_bribe_enemy(enemy_rank):
		return false
	deduct_bribe_cost(enemy_rank)
	return true

func deduct_bribe_cost(enemy_rank: GameConstants.Rank) -> void:
	# If the TRAPO successfully bribes an enemy piece
	# deduct the corresponding cost from the TRAPO wallet
	var cost: int = get_bribe_cost(enemy_rank)
	if check_bribe_success(enemy_rank):
		trapo_wallet -= cost

func total_bribe_value() -> int:
	var total_bribe: int = 0
	for rank in GameConstants.Rank.values():
		if rank != GameConstants.Rank.TRAPO and rank != GameConstants.Rank.FLAG:
			total_bribe += GameConstants.BOUNTIES.get(rank, 0)
	return total_bribe

func visible_tiles_for_piece(rank: GameConstants.Rank) -> int:
	# Returns the number of tiles visible to a piece based on its rank
	return GameConstants.get_vision_range(rank)
