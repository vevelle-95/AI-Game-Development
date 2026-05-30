extends RefCounted
class_name GameConstants

enum Team {PLAYER, AI}

enum Rank {
	TRAPO = -1,
	FLAG = 0,
	SPY = 1,
	PRIVATE = 2,
	SERGEANT = 3,
	LIEUTENANT = 4,
	MAJOR = 5,
	COLONEL = 6,
	GENERAL_3 = 7,
	GENERAL_4 = 8,
	GENERAL_5 = 9
}

const BOUNTIES = {
	Rank.PRIVATE: 10,
	Rank.SERGEANT: 25,
	Rank.LIEUTENANT: 35,
	Rank.MAJOR: 50,
	Rank.COLONEL: 60,
	Rank.GENERAL_3: 70,
	Rank.GENERAL_4: 70,
	Rank.GENERAL_5: 70,
	Rank.SPY: 25,
	Rank.TRAPO: 35
}

const BRIBE_COSTS = {
	Rank.PRIVATE: 20,
	Rank.SERGEANT: 35,
	Rank.LIEUTENANT: 50,
	Rank.MAJOR: 75,
	Rank.COLONEL: 100,
	Rank.GENERAL_3: 150,
	Rank.GENERAL_4: 175,
	Rank.GENERAL_5: 200,
	Rank.SPY: 80,
	Rank.TRAPO: 120
}

static func get_vision_range(rank: Rank) -> int:
	match rank:
		Rank.GENERAL_3, Rank.GENERAL_4, Rank.GENERAL_5:
			return 3
		Rank.COLONEL, Rank.MAJOR, Rank.LIEUTENANT, Rank.TRAPO:
			return 2
		Rank.SERGEANT, Rank.PRIVATE, Rank.SPY:
			return 1
		_:
			return 0
