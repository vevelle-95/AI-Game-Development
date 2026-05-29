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
	Rank.SERGEANT: 15,
	Rank.LIEUTENANT: 20,
	Rank.MAJOR: 30,
	Rank.COLONEL: 40,
	Rank.GENERAL_3: 50,
	Rank.GENERAL_4: 60,
	Rank.GENERAL_5: 75,
	Rank.SPY: 25,
	Rank.TRAPO: 35
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
