class_name ItemData
extends RefCounted
## Every item in the game, in one list. Edit costs, charges and descriptions here.
##
## Fields:
##   id, name, category  - category is "Information", "Movement", "Interference" or "Economy"
##   cost                - the shop price (passives are already priced 1 lower to cover the
##                         1-gold activation fee)
##   passive             - true: must be activated (for a fee) and then works by itself
##   charges, unit       - how long it lasts: that many "uses", "blocks", "landings" or "turns"
##   pool                - "every_shop", "guaranteed" (one shop) or "random" (drawn each game)
##   target              - what the player must choose: "none", "direction", "opponent", ...
##   never_with          - item ids that can't appear in the same game
##   implemented         - false = designed but not built yet (the shop doesn't sell it)
##   secret              - true: the log doesn't say which item was used (traps)
##   description         - shown in the Items and Shop windows

const SELL_RATE := 0.5   # selling gives back this share of the cost, rounded down

## How many copies of an item each shop starts with. Edit the numbers or add
## exceptions to STOCK_OVERRIDES.
const DEFAULT_STOCK := 2
const RARE_STOCK := 1          # for items that cost RARE_COST or more
const RARE_COST := 3
const STOCK_OVERRIDES := {"scout_lens": 3}

const ITEMS := [
	# --- Always in the game -------------------------------------------------
	{"id": "scout_lens", "name": "Scout Lens", "category": "Information", "cost": 1,
		"charges": 1, "unit": "uses", "passive": false, "pool": "every_shop",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Privately shows the type of every space directly connected to yours."},
	{"id": "distraction_bell", "name": "Distraction Bell", "category": "Interference", "cost": 1,
		"charges": 1, "unit": "uses", "passive": false, "pool": "guaranteed",
		"target": "opponent", "never_with": [], "implemented": true,
		"description": "Choose an opponent. On its next move the Goblin heads for them instead of the nearest player."},
	{"id": "prospectors_pick", "name": "Prospector's Pick", "category": "Economy", "cost": 1,
		"charges": 5, "unit": "landings", "passive": true, "pool": "guaranteed",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Passive. Once active, +1 gold each time you land on a Neutral space."},

	# --- Information pool ---------------------------------------------------
	{"id": "crown_compass", "name": "Crown Compass", "category": "Information", "cost": 2,
		"charges": 3, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": ["crown_whisper"], "implemented": true,
		"description": "Shows which exit leads toward the Crown along the shortest walking route."},
	{"id": "danger_bell", "name": "Danger Bell", "category": "Information", "cost": 1,
		"charges": 2, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Tells you whether any connected space is Bad or the Shadow Realm (not which)."},
	{"id": "crown_whisper", "name": "Crown Whisper", "category": "Information", "cost": 2,
		"charges": 2, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": ["crown_compass"], "implemented": true,
		"description": "Tells you how many steps you are from the Crown along the shortest walking route."},
	{"id": "spyglass", "name": "Spyglass", "category": "Information", "cost": 2,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Reveals the type of one random hidden space and how many steps away it is."},

	# --- Movement pool ------------------------------------------------------
	{"id": "wind_step", "name": "Wind Step", "category": "Movement", "cost": 2,
		"charges": 2, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Take a second move this turn. The first space still resolves normally."},
	{"id": "skeleton_key", "name": "Skeleton Key", "category": "Movement", "cost": 2,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "direction", "never_with": [], "implemented": true,
		"description": "Move to the adjacent space in a direction you choose, even with no connection. Counts as your move. Can't enter the Crown."},
	{"id": "blink_stone", "name": "Blink Stone", "category": "Movement", "cost": 2,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Teleport to a random hidden space more than 1 step away. Never the Crown."},
	{"id": "homing_charm", "name": "Homing Charm", "category": "Movement", "cost": 1,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Teleport back to Start (no Start bonus)."},
	{"id": "anchor", "name": "Anchor", "category": "Movement", "cost": 1,
		"charges": 2, "unit": "blocks", "passive": true, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Passive. Blocks harm caused by the game: bad wheel results and the Shadow Realm (and later the Goblin). Asks before blocking a Teleport."},

	# --- Interference pool --------------------------------------------------
	{"id": "thiefs_snare", "secret": true, "name": "Thief's Snare", "category": "Interference", "cost": 2,
		"charges": 2, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Trap on your space. The next player to land there loses 2 gold to you."},
	{"id": "warding_talisman", "name": "Warding Talisman", "category": "Interference", "cost": 1,
		"charges": 2, "unit": "blocks", "passive": true, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Passive. Blocks harm caused by other players (traps, theft, curses, swaps)."},
	{"id": "mud_trap", "secret": true, "name": "Mud Trap", "category": "Interference", "cost": 1,
		"charges": 2, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Trap on your space. The next player to land there loses their next move."},
	{"id": "cursed_coin", "secret": true, "name": "Cursed Coin", "category": "Interference", "cost": 2,
		"charges": 2, "unit": "uses", "passive": false, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Trap on your space. The next player to land there loses 1 gold and spins the Bad wheel."},
	{"id": "chaos_swap", "name": "Chaos Swap", "category": "Interference", "cost": 3,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "swap", "never_with": [], "implemented": true,
		"description": "Swap places with a chosen player, or swap the other two players."},
	{"id": "pickpocket", "name": "Pickpocket", "category": "Interference", "cost": 2,
		"charges": 2, "unit": "uses", "passive": false, "pool": "random",
		"target": "opponent", "never_with": [], "implemented": true,
		"description": "Steal 1 gold from an opponent sharing your space."},
	{"id": "misfortune_curse", "name": "Misfortune Curse", "category": "Interference", "cost": 3,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "opponent", "never_with": [], "implemented": true,
		"description": "Targets the opponent with the most gold; they lose 2 gold at the start of their next turn."},
	{"id": "close_quarters_heist", "name": "Close-Quarters Heist", "category": "Interference", "cost": 4,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "opponent", "never_with": [], "implemented": true,
		"description": "Steal 3 gold from an opponent sharing your space."},

	# --- Economy pool -------------------------------------------------------
	{"id": "bounty_drop", "name": "Bounty Drop", "category": "Economy", "cost": 1,
		"charges": 1, "unit": "uses", "passive": false, "pool": "random",
		"target": "opponent", "never_with": [], "implemented": true,
		"description": "Choose an opponent. 2 gold appears on a random space within 2 steps of them."},
	{"id": "gold_rush", "name": "Gold Rush", "category": "Economy", "cost": 1,
		"charges": 3, "unit": "turns", "passive": true, "pool": "random",
		"target": "none", "never_with": [], "implemented": true,
		"description": "Passive. For your next 3 turns, double gold from wheel spins and space effects."},
]


static func find(item_id: String) -> Dictionary:
	for item in ITEMS:
		if item["id"] == item_id:
			return item
	return {}


## "1 use", "3 uses", "1 turn", "5 landings"... for a number of charges.
static func charge_text(charges: int, unit: String) -> String:
	return "%d %s" % [charges, unit.trim_suffix("s") if charges == 1 else unit]


## Starting stock of an item in each shop that sells it.
static func start_stock(item_id: String) -> int:
	if STOCK_OVERRIDES.has(item_id):
		return STOCK_OVERRIDES[item_id]
	return RARE_STOCK if int(find(item_id).get("cost", 0)) >= RARE_COST else DEFAULT_STOCK


## What the shop pays you for an item: SELL_RATE of its cost, rounded down.
static func sell_price(item_id: String) -> int:
	return floori(int(find(item_id).get("cost", 0)) * SELL_RATE)
