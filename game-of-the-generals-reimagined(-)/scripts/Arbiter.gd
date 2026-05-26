extends Node

enum CombatResult {
	ATTACKER_WINS, 
	DEFENDER_WINS, 
	TIE, 
	GAME_OVER_ATTACKER_WINS, 
	GAME_OVER_DEFENDER_WINS 
}

func resolve_combat(attacker_rank: GameConstants.Rank, defender_rank: GameConstants.Rank) -> CombatResult:
	
	# 1. FLAG CONDITIONS (Instant Game Over)
	if defender_rank == GameConstants.Rank.FLAG:
		return CombatResult.GAME_OVER_ATTACKER_WINS
	if attacker_rank == GameConstants.Rank.FLAG:
		return CombatResult.GAME_OVER_DEFENDER_WINS

	# 2. TIE CONDITION (Same rank = mutual destruction)
	if attacker_rank == defender_rank:
		return CombatResult.TIE
		
	# 3. SPY vs PRIVATE (Private always defeats Spy)
	if attacker_rank == GameConstants.Rank.PRIVATE and defender_rank == GameConstants.Rank.SPY:
		return CombatResult.ATTACKER_WINS
	if attacker_rank == GameConstants.Rank.SPY and defender_rank == GameConstants.Rank.PRIVATE:
		return CombatResult.DEFENDER_WINS
		
	# 4. SPY vs OFFICERS & GENERALS
	var is_defender_general = defender_rank in [GameConstants.Rank.GENERAL_3, GameConstants.Rank.GENERAL_4, GameConstants.Rank.GENERAL_5]
	
	if attacker_rank == GameConstants.Rank.SPY and is_defender_general:
		return CombatResult.ATTACKER_WINS
	elif attacker_rank == GameConstants.Rank.SPY and defender_rank >= GameConstants.Rank.SERGEANT:
		# Spy also defeats standard officers when attacking
		return CombatResult.ATTACKER_WINS
	elif defender_rank == GameConstants.Rank.SPY and attacker_rank >= GameConstants.Rank.SERGEANT:
		# If the Spy is DEFENDING against an officer/general, the attacker wins
		return CombatResult.ATTACKER_WINS

	# 5. TRAPO COMBAT CONDITIONS
	if attacker_rank == GameConstants.Rank.TRAPO:
		return CombatResult.DEFENDER_WINS
	if defender_rank == GameConstants.Rank.TRAPO:
		return CombatResult.ATTACKER_WINS

	# 6. STANDARD HIERARCHY 
	if attacker_rank > defender_rank:
		return CombatResult.ATTACKER_WINS
	else:
		return CombatResult.DEFENDER_WINS
