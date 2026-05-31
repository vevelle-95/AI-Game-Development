extends Node
class_name Arbiter

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

	# 2. TRAPO vs TRAPO (Mutual destruction regardless of bribe)
	if attacker_rank == GameConstants.Rank.TRAPO and defender_rank == GameConstants.Rank.TRAPO:
		return CombatResult.TIE
	
	# 3. TIE CONDITION (Same rank = mutual destruction)
	if attacker_rank == defender_rank:
		return CombatResult.TIE
		
	# 3. SPY vs PRIVATE (Private always defeats Spy)
	if attacker_rank == GameConstants.Rank.PRIVATE and defender_rank == GameConstants.Rank.SPY:
		return CombatResult.ATTACKER_WINS
	if attacker_rank == GameConstants.Rank.SPY and defender_rank == GameConstants.Rank.PRIVATE:
		return CombatResult.DEFENDER_WINS

	# 4. SPY VS EVERYONE ELSE
	if attacker_rank == GameConstants.Rank.SPY:
		return CombatResult.ATTACKER_WINS
	if defender_rank == GameConstants.Rank.SPY:
		return CombatResult.DEFENDER_WINS

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
