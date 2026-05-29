extends Node
class_name GameManager

enum PlayTurn {
	PLAYER1,
	AI
}


func fog_of_war_enabled() -> bool:
	#returns true if the fog of war is enabled, false otherwise
	return true

var current_turn: PlayTurn = PlayTurn.PLAYER1
var game_over: bool = false
var trapo_wallet: int = 0 # TRAPO starts with 0 bribe money

func switch_turn() -> void:
	if current_turn == PlayTurn.PLAYER1:
		current_turn = PlayTurn.AI
	else:
		current_turn = PlayTurn.PLAYER1

func add_kill_bounty(killed_rank: GameConstants.Rank) -> void:
	#for every kill, add the bounty of the killed piece to the TRAPO wallet
	var bounty = GameConstants.BOUNTIES.get(killed_rank, 0)
	trapo_wallet += bounty

func check_bribe_success(enemy_rank: GameConstants.Rank) -> bool:
	#checks if the TRAPO has enough money to bribe the enemy piece based on its rank
	var enemy_bribe = GameConstants.BOUNTIES.get(enemy_rank, 0)
	return trapo_wallet >= enemy_bribe

func deduct_bribe_cost(enemy_rank: GameConstants.Rank) -> void:
	#if the TRAPO successfully bribes an enemy piece
	#deduct the corresponding cost from the TRAPO wallet
	var cost = GameConstants.BOUNTIES.get(enemy_rank, 0)
	if check_bribe_success(enemy_rank) == true:
		trapo_wallet -= cost

func total_bribe_value() -> int:
	var total_bribe = 0
	for rank in GameConstants.Rank.values():
		if rank != GameConstants.Rank.TRAPO and rank != GameConstants.Rank.FLAG:
			total_bribe += GameConstants.BOUNTIES.get(rank, 0)
	return total_bribe


func visible_tiles_for_piece(rank: GameConstants.Rank) -> int:
	#returns the number of tiles visible to a piece based on its rank
	return GameConstants.get_vision_range(rank)
