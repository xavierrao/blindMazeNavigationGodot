class_name ItemData
extends RefCounted
## The shop's item list. Edit freely - the shop reads everything from here.
## "max" is how many of this item one player may buy in total (-1 = unlimited).
## Item EFFECTS are not implemented yet; for now items can only be bought.
##
## These are the items from the old README, kept as placeholders.

const ITEMS := [
	{"id": "scout_lens", "name": "Scout Lens", "cost": 2, "max": -1,
		"description": "Reveals all adjacent connected spaces."},
	{"id": "chaos_swap", "name": "Chaos Swap", "cost": 4, "max": 2,
		"description": "Randomly swaps two players' positions."},
	{"id": "crown_compass", "name": "Crown Compass", "cost": 3, "max": 3,
		"description": "Shows which direction leads closer to the Crown."},
	{"id": "thiefs_snare", "name": "Thief's Snare", "cost": 3, "max": 2,
		"description": "Set a trap that steals 2 gold from the next player."},
	{"id": "bounty_drop", "name": "Bounty Drop", "cost": 2, "max": -1,
		"description": "Place 3 gold on a random adjacent space."},
	{"id": "misfortune_curse", "name": "Misfortune Curse", "cost": 5, "max": 1,
		"description": "Force a player to lose 2 gold."},
	{"id": "close_quarters_heist", "name": "Close-Quarters Heist", "cost": 4, "max": 2,
		"description": "Steal 4 gold if sharing a space."},
	{"id": "wandering_goblin", "name": "Wandering Goblin", "cost": 5, "max": 1,
		"description": "Spawns a goblin that steals from players."},
	{"id": "warding_talisman", "name": "Warding Talisman", "cost": 6, "max": 2,
		"description": "Protects from one negative effect."},
]


static func find(item_id: String) -> Dictionary:
	for item in ITEMS:
		if item["id"] == item_id:
			return item
	return {}
