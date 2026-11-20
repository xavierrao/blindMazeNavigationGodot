class_name GameState
extends RefCounted
## Rules and data for Blind Crown Quest. There is no drawing or UI code in here,
## so any view (the board, or the later "players and their spaces" view) can sit
## on top of it, and it can later run on a host/server for multiplayer.
##
## Typical turn:
##   state.legal_moves()     # {"North": 7, ...} - or {} if you can't move
##   state.move("North")     # lands on a space and triggers its effect
##   state.spin()            # only when state.pending says a wheel is waiting
##   state.buy("scout_lens") # only while on a Shop space
##   state.use_item("wind_step")      # items: before moving or after your space's effect
##   state.activate_item("gold_rush") # passive items: pay the fee, then they work by themselves
##   state.end_turn()

signal changed                 # anything changed -> refresh the views
signal message(text: String)   # something worth telling the players
## `blocked` is true when the result is harmful but a protective item (Anchor or
## Warding Talisman) will stop it, so the wheel pop-up can say so.
signal wheel_spun(wheel_name: String, slices: Array, index: int, blocked: bool)
signal private_message(player_index: int, text: String)   # information only that player may see

const GRID_SIZE := 5
const CROWN_GOLD_REQUIRED := 10      # gold needed (and paid) to win at the Crown
const START_GOLD_BONUS := 1          # gold for landing on the Start space...
const START_BONUS_GOLD_LIMIT := 3    # ...but only if you have FEWER than this much gold
const HAND_LIMIT := 3                # items you can hold (active passives don't count)
const ACTIVATION_FEE := 1            # gold to switch on a passive item
const RESTOCK_ROUNDS := 4            # full rounds after selling out before one copy returns
const GOBLIN_MILESTONES := [3, 6, 9] # the Goblin appears when the FIRST player reaches each
const GOBLIN_STEAL := 1              # gold it takes from every free player it catches
## Gold from these sources is doubled while Gold Rush is running.
const GOLD_RUSH_SOURCES := ["start", "good", "pick"]

## Compass directions, clockwise from North, and their (row, column) steps.
const DIRECTIONS := ["North", "NorthEast", "East", "SouthEast", "South", "SouthWest", "West", "NorthWest"]
const DIRECTION_OFFSETS := {
	"North": Vector2i(-1, 0), "NorthEast": Vector2i(-1, 1), "East": Vector2i(0, 1),
	"SouthEast": Vector2i(1, 1), "South": Vector2i(1, 0), "SouthWest": Vector2i(1, -1),
	"West": Vector2i(0, -1), "NorthWest": Vector2i(-1, -1),
}

## Memory Mode (default): a space is face-up only while a player stands on it.
## Turn it off and spaces stay face-up once they have been visited.
var memory_mode := true

var spaces: Array = []   # from GridGenerator: {"id", "type", "connections"}
var players: Array = []  # see setup() for the fields
var current_player := 0
var round_number := 1
var has_moved := false   # has the current player used their move/spin this turn?
var extra_moves := 0     # extra moves still available this turn (Wind Step)
var discovered := {}     # space id -> true, for when Memory Mode is off
var shops := {}          # Shop space id -> {"items": [ids], "stock": {id: n}, "restock": {id: rounds left}}
var announced_items: Array = []   # item ids for sale somewhere on the map (not which shop)
## What must be dealt with before anything else. Either
##   {"kind": "wheel", "wheel": "good"|"bad"|"shadow", "source": "game"|"player"}  - a wheel to spin, or
##   {"kind": "choice", "choice": "anchor_teleport", "player": index}               - a yes/no question
## or {} when nothing is waiting. "source" says who caused a wheel (the game's
## tile, or another player's trap), which decides which item can protect you.
var pending := {}
## Things that came up at the same time as `pending` and are waiting their turn
## (for example a Good wheel and then the Cursed Coin's wheel).
var pending_queue: Array = []
## Hidden traps: space id -> [{"owner": player index, "kind": item id}], oldest first.
var traps := {}
## Misfortune Curses waiting to strike: {"target": player index, "owner": player index}.
var curses: Array = []

## The Wandering Goblin (see section 8 of the rules doc). Players never see it
## unless it shares a space with them; only the log hints where it goes.
var goblin_enabled := true       # switch off to play (or test) without it
var goblin_min_distance := 3     # it spawns/scatters at least this many steps from every free player
var goblin_space := -1           # -1 = not on the board yet
var goblin_lure := -1            # player index a Distraction Bell sent it after, or -1
var goblin_milestones := {}      # gold milestones already triggered
## Hidden gold lying on spaces from Bounty Drop: space id -> gold.
var bounties := {}
var winner := -1         # player index once someone wins
var start_id := 12

## One master seed drives several independent random streams, so changing (say) a
## wheel never changes the map you get from the same seed.
var game_seed := 0
var rng := RandomNumberGenerator.new()          # "events": wheel spins, teleports, other results
var shop_rng := RandomNumberGenerator.new()     # "shops": stock and placement (used by shops v2)
var goblin_rng := RandomNumberGenerator.new()   # "goblin": spawns, scatters, ties (used by the Goblin)

## Counters for the bot simulator and balance checks.
var stats := {}


func setup(player_names: Array, start_space_id: int = 12, seed_value: int = -1) -> bool:
	start_id = start_space_id
	if seed_value >= 0:
		game_seed = seed_value
	else:
		var seeder := RandomNumberGenerator.new()
		seeder.randomize()
		game_seed = seeder.randi_range(100000, 999999)   # short enough to read out to a friend
	rng.seed = derive_seed(game_seed, "events")
	shop_rng.seed = derive_seed(game_seed, "shops")
	goblin_rng.seed = derive_seed(game_seed, "goblin")

	spaces = GridGenerator.new().create_grid(start_id, derive_seed(game_seed, "map"))
	if spaces.is_empty():
		return false
	stats = {"gold_gained": {}, "gold_lost": {}, "landings": {}, "items_bought": {},
		"items_used": {}, "traps_fired": {}, "shadow_spins": 0, "turns": 0}

	players.clear()
	for player_name in player_names:
		players.append({
			"name": str(player_name),
			"position": start_id,
			"gold": 0,
			"trapped": false,     # in the Shadow Realm
			"shadow_spins": 0,    # real spins during the CURRENT stay (not counting being sent)
			"skip_move": false,   # a Mud Trap took their next move
			"hand": [],           # items held: {"id", "charges"} - at most HAND_LIMIT
			"active": [],         # switched-on passives: {"id", "charges", "fresh"}
		})
	current_player = 0
	round_number = 1
	has_moved = false
	extra_moves = 0
	pending = {}
	pending_queue = []
	traps = {}
	curses = []
	goblin_space = -1
	goblin_lure = -1
	goblin_milestones = {}
	bounties = {}
	winner = -1
	discovered = {start_id: true}

	var shop_ids: Array = []
	for space in spaces:
		if space["type"] == "Shop":
			shop_ids.append(space["id"])
	var built := ShopBuilder.build(shop_ids, shop_rng)
	shops = built["shops"]
	announced_items = built["announced"]
	var names: Array = []
	for item_id in announced_items:
		names.append(ItemData.find(item_id)["name"])
	message.emit("Items for sale somewhere on the map: " + ", ".join(names) + ".")

	changed.emit()
	return true


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func current() -> Dictionary:
	return players[current_player]


func space_type(id: int) -> String:
	return spaces[id]["type"]


## Which player indices are standing on this space.
func players_on(id: int) -> Array:
	var result: Array = []
	for i in players.size():
		if players[i]["position"] == id:
			result.append(i)
	return result


## Is this space face-up right now?
func is_face_up(id: int) -> bool:
	if not players_on(id).is_empty():
		return true
	return not memory_mode and discovered.has(id)


## Directions the current player can move this turn: {"North": target_id, ...}.
## Empty if they already acted, a wheel is waiting, they are trapped, or the game is over.
func legal_moves() -> Dictionary:
	var result := {}
	if winner >= 0 or not has_move_available():
		return result
	var from: int = current()["position"]
	for target in spaces[from]["connections"]:
		var direction := direction_between(from, target)
		if not result.has(direction) or distance(from, target) < distance(from, result[direction]):
			result[direction] = target
	return result


## Can the current player still make a move this turn?
func has_move_available() -> bool:
	return winner < 0 and pending.is_empty() and not current()["trapped"] \
		and (not has_moved or extra_moves > 0)


func can_end_turn() -> bool:
	if winner >= 0 or not pending.is_empty():
		return false
	return has_moved or legal_moves().is_empty()


## The slices of the wheel that is waiting to be spun ([] if none).
## Which player the waiting wheel or question belongs to. Usually the player whose
## turn it is, but a Chaos Swap can make someone land on a wheel space during
## another player's turn.
func pending_player() -> int:
	return int(pending.get("player", current_player))


func pending_slices() -> Array:
	if pending.get("kind", "") != "wheel":
		return []
	return WheelData.get_wheel(pending["wheel"], players[pending_player()]["shadow_spins"])


func can_shop() -> bool:
	return winner < 0 and pending.is_empty() and not current()["trapped"] \
		and shops.has(int(current()["position"]))


## The shop on the current player's space ({} if they aren't on one).
func shop_here() -> Dictionary:
	return shops.get(int(current()["position"]), {})


## What the shop on the current player's space has: [{"item": item data, "stock": n,
## "restocking": bool}], in the shop's own order.
func shop_listing() -> Array:
	var result: Array = []
	var shop := shop_here()
	if shop.is_empty():
		return result
	for item_id in shop["items"]:
		result.append({
			"item": ItemData.find(item_id),
			"stock": int(shop["stock"][item_id]),
			"restocking": shop["restock"].has(item_id),
		})
	return result


## The entry for an item in a player's hand ({} if they don't hold it).
func hand_entry(player_index: int, item_id: String) -> Dictionary:
	for entry in players[player_index]["hand"]:
		if entry["id"] == item_id:
			return entry
	return {}


## The entry for a switched-on passive ({} if it isn't running).
func active_effect(player_index: int, item_id: String) -> Dictionary:
	for effect in players[player_index]["active"]:
		if effect["id"] == item_id:
			return effect
	return {}


## "" if the current player may use items right now, otherwise why not.
## Items work before you move or after your space's effect has fully resolved -
## never while a wheel is waiting, never while trapped.
func items_blocked_reason() -> String:
	if winner >= 0:
		return "The game is over."
	if pending.get("kind", "") == "wheel":
		return "Finish the wheel first."
	if not pending.is_empty():
		return "Answer the prompt first."
	if current()["trapped"]:
		return "You can't use items while trapped in the Shadow Realm."
	return ""


## "" if the current player can buy this item right now, otherwise why not.
func buy_problem(item_id: String) -> String:
	var item := ItemData.find(item_id)
	if item.is_empty() or not item["implemented"]:
		return "That item isn't for sale."
	if not can_shop():
		return "You must be on a Shop space."
	var shop := shop_here()
	if not shop["items"].has(item_id):
		return "This shop doesn't sell that."
	if int(shop["stock"][item_id]) <= 0:
		return "Out of stock."
	var player := current()
	if player["hand"].size() >= HAND_LIMIT:
		return "Your hand is full (%d items)." % HAND_LIMIT
	if not hand_entry(current_player, item_id).is_empty():
		return "You already hold this item."
	if int(player["gold"]) < int(item["cost"]):
		return "Not enough gold."
	return ""


## "" if the current player can sell this item right now, otherwise why not.
func sell_problem(item_id: String) -> String:
	if not can_shop():
		return "You must be on a Shop space."
	var entry := hand_entry(current_player, item_id)
	if entry.is_empty():
		return "You aren't holding that item."
	if int(entry["charges"]) < int(ItemData.find(item_id)["charges"]):
		return "Partly used items can't be sold."
	return ""


## "" if the current player can use this (non-passive) item right now.
## `params` holds any choice the item needs, e.g. {"direction": "North"}.
func use_problem(item_id: String, params: Dictionary = {}) -> String:
	var item := ItemData.find(item_id)
	if item.is_empty() or hand_entry(current_player, item_id).is_empty():
		return "You aren't holding that item."
	var blocked := items_blocked_reason()
	if blocked != "":
		return blocked
	if item["passive"]:
		return "Passive items are activated, not used."
	return ItemEffects.problem(self, item_id, params)


## "" if the current player can activate this passive item right now.
func activate_problem(item_id: String) -> String:
	var item := ItemData.find(item_id)
	if item.is_empty() or not item["passive"]:
		return "That item isn't passive."
	if hand_entry(current_player, item_id).is_empty():
		return "You aren't holding that item."
	var blocked := items_blocked_reason()
	if blocked != "":
		return blocked
	if not active_effect(current_player, item_id).is_empty():
		return "That effect is already running."
	if int(current()["gold"]) < ACTIVATION_FEE:
		return "Activating costs %d gold." % ACTIVATION_FEE
	return ""


## Where the Crown is.
func crown_id() -> int:
	for space in spaces:
		if space["type"] == "Crown":
			return space["id"]
	return -1


## Shadow Realm and Teleport spaces can be landed on but never walked through.
func can_walk_through(id: int) -> bool:
	var type_name := space_type(id)
	return type_name != "Shadow Realm" and type_name != "Teleport"


## Walking steps from every space to `target`, never routing through a space you
## can't walk on from. ({space id: steps}; spaces with no route are missing.)
func walking_steps_to(target: int) -> Dictionary:
	var steps := {target: 0}
	var queue: Array = [target]
	while not queue.is_empty():
		var current_id: int = queue.pop_front()
		if current_id != target and not can_walk_through(current_id):
			continue
		for next_id in spaces[current_id]["connections"]:
			if not steps.has(next_id):
				steps[next_id] = int(steps[current_id]) + 1
				queue.append(next_id)
	return steps


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func move(direction: String) -> bool:
	var moves := legal_moves()
	if not moves.has(direction):
		return false
	_consume_move()
	_land(current_player, moves[direction], "%s moved %s and " % [current()["name"], direction])
	changed.emit()
	return true


## Spin the wheel that is waiting (Good, Bad or Shadow) for the current player.
func spin() -> bool:
	if pending.get("kind", "") != "wheel":
		return false
	var who := pending_player()
	var wheel_name: String = pending["wheel"]
	var slices := pending_slices()
	var index := rng.randi_range(0, slices.size() - 1)
	var slice: Dictionary = slices[index]
	var source := str(pending.get("source", "game"))
	var will_be_blocked := wheel_name != "shadow" and _slice_is_harmful(who, slice) \
		and not active_effect(who, _guard_item(source)).is_empty()

	pending = {}
	if who == current_player:
		has_moved = true   # spinning uses up the turn's move/spin
	if wheel_name == "shadow":
		players[who]["shadow_spins"] = int(players[who]["shadow_spins"]) + 1
		stats["shadow_spins"] = int(stats["shadow_spins"]) + 1

	wheel_spun.emit(wheel_name, slices, index, will_be_blocked)
	_apply_slice(who, slice, wheel_name, source)
	_advance_pending()
	changed.emit()
	return true


func buy(item_id: String) -> bool:
	if buy_problem(item_id) != "":
		return false
	var item := ItemData.find(item_id)
	var player := current()
	player["gold"] = int(player["gold"]) - int(item["cost"])
	player["hand"].append({"id": item_id, "charges": item["charges"]})
	var shop := shop_here()
	shop["stock"][item_id] = int(shop["stock"][item_id]) - 1
	if int(shop["stock"][item_id]) == 0:
		# Sold out: one copy returns at the end of the 4th FULL round after this one.
		shop["restock"][item_id] = RESTOCK_ROUNDS + 1
	_count("items_bought", item_id, 1)
	message.emit("%s bought %s for %d gold." % [player["name"], item["name"], item["cost"]])
	changed.emit()
	return true


func sell(item_id: String) -> bool:
	if sell_problem(item_id) != "":
		return false
	var price := ItemData.sell_price(item_id)
	_remove_from_hand(current_player, item_id)
	_add_gold(current_player, price, "sell")
	message.emit("%s sold %s for %d gold." % [current()["name"], ItemData.find(item_id)["name"], price])
	changed.emit()
	return true


## Use a (non-passive) item from your hand. Each use spends one charge; the item
## leaves your hand when its last charge is spent.
func use_item(item_id: String, params: Dictionary = {}) -> bool:
	if use_problem(item_id, params) != "":
		return false
	var item := ItemData.find(item_id)
	var entry := hand_entry(current_player, item_id)
	entry["charges"] = int(entry["charges"]) - 1
	if int(entry["charges"]) <= 0:
		_remove_from_hand(current_player, item_id)
	_count("items_used", item_id, 1)
	if item.get("secret", false):
		message.emit("%s is up to something..." % current()["name"])   # don't reveal what
	else:
		message.emit("%s used %s." % [current()["name"], item["name"]])
	ItemEffects.use(self, current_player, item_id, params)
	changed.emit()
	return true


## Switch on a passive item: pay the fee, and it moves out of your hand (freeing
## the slot) and keeps working until it runs out.
func activate_item(item_id: String) -> bool:
	if activate_problem(item_id) != "":
		return false
	var item := ItemData.find(item_id)
	_remove_from_hand(current_player, item_id)
	_add_gold(current_player, -ACTIVATION_FEE, "activation")
	current()["active"].append({"id": item_id, "charges": item["charges"], "fresh": true})
	message.emit("%s pays %d gold to activate %s." % [current()["name"], ACTIVATION_FEE, item["name"]])
	changed.emit()
	return true


func end_turn() -> bool:
	if not can_end_turn():
		return false
	stats["turns"] = int(stats["turns"]) + 1
	_tick_turn_effects(current_player)
	current_player = (current_player + 1) % players.size()
	if current_player == 0:
		round_number += 1
		_tick_shop_restocks()
		_goblin_acts()
	has_moved = false
	extra_moves = 0
	message.emit("%s's turn." % current()["name"])
	_begin_turn()
	changed.emit()
	return true


# ---------------------------------------------------------------------------
# Space effects
# ---------------------------------------------------------------------------

# Put a player on a space and trigger that space's effect.
# `prefix` is the start of the log sentence, e.g. "Alice moved West and ".
func _land(player_index: int, target: int, prefix: String, start_bonus: bool = true) -> void:
	var player: Dictionary = players[player_index]
	player["position"] = target
	discovered[target] = true

	var type_name := space_type(target)
	_count("landings", type_name, 1)
	var named := type_name == "Start" or type_name == "Crown"
	message.emit("%slanded on %s %s%s." % [
		prefix, "the" if named else "a", type_name, "" if named else " space"])

	_collect_bounty(player_index, target)

	match type_name:
		"Start":
			if start_bonus:
				if int(player["gold"]) < START_BONUS_GOLD_LIMIT:
					var gained := _add_gold(player_index, START_GOLD_BONUS, "start")
					message.emit("%s gains %d gold from Start." % [player["name"], gained])
				else:
					message.emit("%s has %d gold or more, so Start gives no bonus." % [
						player["name"], START_BONUS_GOLD_LIMIT])
		"Neutral":
			_prospectors_pick_bonus(player_index)
		"Good":
			_queue_pending({"kind": "wheel", "wheel": "good", "player": player_index})
		"Bad":
			_queue_pending({"kind": "wheel", "wheel": "bad", "player": player_index})
		"Teleport":
			if active_effect(player_index, "anchor").is_empty():
				_teleport(player_index)
			else:
				# An Anchor holder chooses: stay put, or be teleported.
				_queue_pending({"kind": "choice", "choice": "anchor_teleport", "player": player_index})
		"Shadow Realm":
			if _try_block(player_index, "game", "the Shadow Realm"):
				message.emit("%s stays free." % player["name"])
			else:
				message.emit("%s is trapped in the Shadow Realm!" % player["name"])
				_trap(player_index)
		"Crown":
			_check_crown(player_index)
		"Shop":
			message.emit("%s can shop here." % player["name"])
		"Combat":
			message.emit("Combat isn't built yet - nothing happens.")

	# Traps on the space go off after the space's own effect - but never once
	# someone has already won by reaching the Crown.
	if winner < 0:
		_trigger_trap(player_index, target)
	if winner < 0 and goblin_space == target:
		_goblin_collide()   # walked into the Goblin


# Random space MORE THAN ONE connection step away. Never another Teleport (no
# chains) and never the Crown (no accidental instant wins). Its effect then
# happens as normal.
func _teleport(player_index: int) -> void:
	var player: Dictionary = players[player_index]
	var from: int = player["position"]
	var steps := steps_from(from)
	var options: Array = []
	for space in spaces:
		var id: int = space["id"]
		if int(steps.get(id, 99)) > 1 and space["type"] != "Crown" and space["type"] != "Teleport":
			options.append(id)
	if options.is_empty():
		message.emit("The teleporter fizzles.")
		return
	var destination: int = options[rng.randi_range(0, options.size() - 1)]
	_land(player_index, destination, "%s was teleported and " % player["name"])


func _check_crown(player_index: int) -> void:
	var player: Dictionary = players[player_index]
	if int(player["gold"]) >= CROWN_GOLD_REQUIRED:
		player["gold"] = int(player["gold"]) - CROWN_GOLD_REQUIRED
		winner = player_index
		message.emit("%s pays %d gold and claims the Crown - %s wins!" % [
			player["name"], CROWN_GOLD_REQUIRED, player["name"]])
	else:
		message.emit("The Crown needs %d gold, but %s only has %d." % [
			CROWN_GOLD_REQUIRED, player["name"], player["gold"]])


# Changes a player's gold (never below 0) and returns how much it really changed by.
# `source` is only used for the statistics ("start", "good", "bad", ...).
func _add_gold(player_index: int, amount: int, source: String) -> int:
	var player: Dictionary = players[player_index]
	if amount > 0 and GOLD_RUSH_SOURCES.has(source) and _gold_rush_running(player_index):
		amount *= 2
	var before: int = player["gold"]
	player["gold"] = maxi(0, before + amount)
	var change: int = int(player["gold"]) - before
	if change > 0:
		_count("gold_gained", source, change)
		_check_goblin_milestones(int(player["gold"]))
	elif change < 0:
		_count("gold_lost", source, -change)
	return change


func _count(group: String, key: String, amount: int) -> void:
	var counters: Dictionary = stats[group]
	counters[key] = int(counters.get(key, 0)) + amount


# What a wheel slice does.
func _apply_slice(player_index: int, slice: Dictionary, wheel_name: String, source: String = "game") -> void:
	var player: Dictionary = players[player_index]
	var who: String = player["name"]
	# Harmful results from the good/bad wheels can be blocked. (Shadow wheel results
	# are never "blocked": escaping must always work, and failing is not new harm.)
	if wheel_name != "shadow" and _slice_is_harmful(player_index, slice) \
			and _try_block(player_index, source, "this result"):
		return
	match slice["effect"]:
		"gold":
			var change := _add_gold(player_index, slice["amount"], wheel_name)
			if change > 0:
				message.emit("%s gains %d gold." % [who, change])
			elif change < 0:
				message.emit("%s loses %d gold." % [who, -change])
			else:
				message.emit("%s has no gold to lose." % who)
		"nothing":
			message.emit("Nothing happens.")
		"to_shadow":
			player["position"] = _shadow_space_id()
			discovered[player["position"]] = true
			message.emit("%s is sent to the Shadow Realm!" % who)
			_trap(player_index)
		"return_home":
			player["trapped"] = false
			player["shadow_spins"] = 0
			player["position"] = start_id
			discovered[start_id] = true
			message.emit("%s escapes the Shadow Realm and returns to Start!" % who)
		"stay":
			message.emit("%s is still trapped in the Shadow Realm." % who)
			_check_mass_escape()


# ---------------------------------------------------------------------------
# The Wandering Goblin
# ---------------------------------------------------------------------------

# Called whenever a player gains gold. The first player to reach 3, 6 and 9 gold
# each wakes the Goblin (or, if it is already out, scares it somewhere new).
# Jumping over a milestone counts, and one jump triggers only one appearance.
func _check_goblin_milestones(gold: int) -> void:
	if not goblin_enabled:
		return
	var triggered := false
	for milestone in GOBLIN_MILESTONES:
		if gold >= int(milestone) and not goblin_milestones.has(milestone):
			goblin_milestones[milestone] = true
			triggered = true
	if not triggered:
		return
	var destination := _goblin_pick_space(goblin_space)
	if destination < 0:
		return
	if goblin_space < 0:
		message.emit("A Wandering Goblin appears somewhere on the board!")
	else:
		message.emit("The Wandering Goblin is startled and slips away to somewhere new!")
		goblin_lure = -1   # a relocation resets its targeting
	goblin_space = destination


func _free_players() -> Array:
	var result: Array = []
	for i in players.size():
		if not players[i]["trapped"]:
			result.append(i)
	return result


# Where the Goblin appears or scatters to: nobody standing there, never the Shadow
# Realm, and (when it is already on the board) more than 1 step from where it was.
# It prefers spaces at least goblin_min_distance steps from every free player; if
# there are none, the space farthest from the nearest free player.
func _goblin_pick_space(origin: int) -> int:
	var maps: Array = []
	for i in _free_players():
		maps.append(steps_from(int(players[i]["position"])))
	var origin_steps := steps_from(origin) if origin >= 0 else {}
	var far_enough: Array = []
	var farthest: Array = []
	var best_distance := -1
	for space in spaces:
		var id: int = space["id"]
		if space["type"] == "Shadow Realm" or not players_on(id).is_empty():
			continue
		if origin >= 0 and int(origin_steps.get(id, 99)) <= 1:
			continue
		var nearest := 99
		for steps in maps:
			nearest = mini(nearest, int(steps.get(id, 99)))
		if nearest >= goblin_min_distance:
			far_enough.append(id)
		if nearest > best_distance:
			best_distance = nearest
			farthest = [id]
		elif nearest == best_distance:
			farthest.append(id)
	var pool: Array = far_enough if not far_enough.is_empty() else farthest
	if pool.is_empty():
		return -1
	return pool[goblin_rng.randi_range(0, pool.size() - 1)]


# End of a full round: the Goblin takes one step toward the nearest free player
# (ties are random), or toward the player a Distraction Bell named.
func _goblin_acts() -> void:
	if not goblin_enabled or goblin_space < 0 or winner >= 0:
		return
	var target := _goblin_target()
	if target < 0:
		return
	var destination := _goblin_step_toward(int(players[target]["position"]))
	if destination == goblin_space:
		return
	goblin_space = destination
	message.emit("The Goblin moves onto a %s space." % space_type(destination))
	_goblin_collide()


func _goblin_target() -> int:
	var free := _free_players()
	if free.is_empty():
		return -1
	if goblin_lure >= 0:
		var lured := goblin_lure
		goblin_lure = -1          # used up (or wasted, if they are trapped)
		if free.has(lured):
			return lured
	var steps := steps_from(goblin_space)
	var closest := 1000
	var tied: Array = []
	for i in free:
		var d := int(steps.get(int(players[i]["position"]), 999))
		if d < closest:
			closest = d
			tied = [i]
		elif d == closest:
			tied.append(i)
	return tied[goblin_rng.randi_range(0, tied.size() - 1)]


# The neighbour of the Goblin's space that is nearest to `target_space`.
func _goblin_step_toward(target_space: int) -> int:
	var steps := steps_from(target_space)
	var best := int(steps.get(goblin_space, 999))
	var options: Array = []
	for next_id in spaces[goblin_space]["connections"]:
		var d := int(steps.get(next_id, 999))
		if d < best:
			best = d
			options = [next_id]
		elif d == best and not options.is_empty():
			options.append(next_id)
	if options.is_empty():
		return goblin_space
	return options[goblin_rng.randi_range(0, options.size() - 1)]


# The Goblin and one or more free players share a space: it steals from each
# (the Anchor can stop it), then leaps away.
func _goblin_collide() -> void:
	var victims: Array = []
	for i in players_on(goblin_space):
		if not players[i]["trapped"]:
			victims.append(i)
	if victims.is_empty():
		return
	var names: Array = []
	for i in victims:
		names.append(players[i]["name"])
	message.emit("The Goblin pounces on %s!" % " and ".join(names))
	for i in victims:
		if _try_block(i, "game", "the Goblin's theft"):
			continue
		var lost := -_add_gold(i, -GOBLIN_STEAL, "goblin")   # the gold leaves the game
		if lost > 0:
			message.emit("%s is robbed of %d gold!" % [players[i]["name"], lost])
		else:
			message.emit("%s has no gold for the Goblin to steal." % players[i]["name"])
	var destination := _goblin_pick_space(goblin_space)
	if destination >= 0:
		goblin_space = destination
		message.emit("The Goblin leaps away onto a %s space." % space_type(destination))


# ---------------------------------------------------------------------------
# Chaos Swap
# ---------------------------------------------------------------------------

## Two players trade places and each then "lands" on their new space (its effect,
## traps, bounty gold and the Goblin all apply). `user` is who played the item:
## they can't block their own swap, but the Warding Talisman of either OTHER
## swapped player stops the whole thing. Returns false if it was blocked.
func swap_players(a: int, b: int, user: int) -> bool:
	for swapped in [a, b]:
		if swapped != user and _try_block(swapped, "player", "the Chaos Swap"):
			return false
	var space_a: int = players[a]["position"]
	var space_b: int = players[b]["position"]
	players[a]["position"] = space_b
	players[b]["position"] = space_a
	_land(a, space_b, "%s swapped places with %s and " % [players[a]["name"], players[b]["name"]])
	if winner < 0:
		_land(b, space_a, "%s swapped places with %s and " % [players[b]["name"], players[a]["name"]])
	return true


# ---------------------------------------------------------------------------
# Bounty Drop gold
# ---------------------------------------------------------------------------

func place_bounty(space_id: int, amount: int) -> void:
	bounties[space_id] = int(bounties.get(space_id, 0)) + amount


# Whoever lands on a space with hidden gold takes it (never doubled by Gold Rush).
func _collect_bounty(player_index: int, space_id: int) -> void:
	if not bounties.has(space_id):
		return
	var amount: int = bounties[space_id]
	bounties.erase(space_id)
	var gained := _add_gold(player_index, amount, "bounty")
	message.emit("%s finds %d gold lying on the ground!" % [players[player_index]["name"], gained])


# ---------------------------------------------------------------------------
# Waiting wheels and prompts
# ---------------------------------------------------------------------------

# Something needs the player's attention. If something is already waiting, it
# goes to the back of the line. (Wheels and prompts belong to the current player.)
func _queue_pending(entry: Dictionary) -> void:
	if not entry.has("player"):
		entry["player"] = current_player
	if pending.is_empty():
		pending = entry
	else:
		pending_queue.append(entry)


func _advance_pending() -> void:
	if pending.is_empty() and not pending_queue.is_empty():
		pending = pending_queue.pop_front()


# ---------------------------------------------------------------------------
# Traps, stealing and curses
# ---------------------------------------------------------------------------

## Hide a trap on the space the player is standing on.
func place_trap(player_index: int, kind: String) -> void:
	var space_id: int = players[player_index]["position"]
	if not traps.has(space_id):
		traps[space_id] = []
	traps[space_id].append({"owner": player_index, "kind": kind})


## The traps a player has set, for showing to them only: [{"kind", "space", "space_type"}].
func traps_owned_by(player_index: int) -> Array:
	var result: Array = []
	for space_id in traps:
		for trap in traps[space_id]:
			if int(trap["owner"]) == player_index:
				result.append({"kind": trap["kind"], "space": space_id, "space_type": space_type(space_id)})
	return result


# One trap per landing, oldest first. The trap is used up even if it is blocked.
func _trigger_trap(player_index: int, space_id: int) -> void:
	if not traps.has(space_id):
		return
	var queue: Array = traps[space_id]
	var trap: Dictionary = queue.pop_front()
	if queue.is_empty():
		traps.erase(space_id)
	var kind: String = trap["kind"]
	var owner: int = trap["owner"]
	var victim: Dictionary = players[player_index]
	_count("traps_fired", kind, 1)
	message.emit("%s steps on %s's %s!" % [
		victim["name"], players[owner]["name"], ItemData.find(kind)["name"]])
	if _try_block(player_index, "player", "the trap"):
		return
	match kind:
		"thiefs_snare":
			var moved := _transfer_gold(player_index, owner, ItemEffects.SNARE_GOLD)
			if moved > 0:
				message.emit("%s loses %d gold to %s!" % [victim["name"], moved, players[owner]["name"]])
			else:
				message.emit("%s has no gold for the Snare to take." % victim["name"])
		"mud_trap":
			_apply_mud(player_index)
		"cursed_coin":
			var lost := -_add_gold(player_index, -ItemEffects.COIN_GOLD, "coin")
			if lost > 0:
				message.emit("%s loses %d gold and the coin spins the Bad wheel!" % [victim["name"], lost])
			else:
				message.emit("The coin spins the Bad wheel for %s!" % victim["name"])
			_queue_pending({"kind": "wheel", "wheel": "bad", "source": "player",
				"note": "Cursed Coin", "player": player_index})


# The Mud Trap takes the player's NEXT move: the one they haven't made yet this
# turn, or their extra move, or else the move of their next turn.
func _apply_mud(player_index: int) -> void:
	var who: String = players[player_index]["name"]
	if player_index == current_player and not has_moved:
		has_moved = true
		message.emit("%s is stuck in the mud and loses this turn's move!" % who)
	elif player_index == current_player and extra_moves > 0:
		extra_moves -= 1
		message.emit("%s is stuck in the mud and loses their extra move!" % who)
	else:
		players[player_index]["skip_move"] = true
		message.emit("%s is stuck in the mud and will lose their next move!" % who)


## Take up to `amount` gold from `victim` for `thief` (never doubled by Gold Rush).
## Returns how much was really taken.
func _transfer_gold(victim: int, thief: int, amount: int) -> int:
	var moved := mini(amount, int(players[victim]["gold"]))
	if moved <= 0:
		return 0
	_add_gold(victim, -moved, "stolen")
	_add_gold(thief, moved, "steal")
	return moved


## A theft by another player (Pickpocket, Heist). The victim's Warding Talisman
## stops it. Returns how much was taken (0 if blocked).
func steal_gold(thief: int, victim: int, amount: int, what: String) -> int:
	if _try_block(victim, "player", what):
		return 0
	return _transfer_gold(victim, thief, amount)


# At the start of a player's turn, any Misfortune Curse aimed at them strikes.
func _resolve_curses(player_index: int) -> void:
	for i in range(curses.size() - 1, -1, -1):
		if int(curses[i]["target"]) != player_index:
			continue
		curses.remove_at(i)
		if _try_block(player_index, "player", "the Misfortune Curse"):
			continue
		var lost := -_add_gold(player_index, -ItemEffects.CURSE_GOLD, "curse")
		if lost > 0:
			message.emit("%s is hit by a Misfortune Curse and loses %d gold!" % [players[player_index]["name"], lost])
		else:
			message.emit("%s is hit by a Misfortune Curse but has no gold to lose." % players[player_index]["name"])


# ---------------------------------------------------------------------------
# Protection (Anchor and Warding Talisman)
# ---------------------------------------------------------------------------
# A protective passive only spends a charge when it really stops something
# harmful. The ORIGINAL source decides which item protects: harm from the game's
# own spaces and wheels is Anchor's job, harm from other players is the
# Warding Talisman's (even when it works through a wheel, like Cursed Coin).

func _guard_item(source: String) -> String:
	return "anchor" if source == "game" else "warding_talisman"


# Would this wheel result hurt the player right now?
# (Losing gold only counts if they have gold to lose.)
func _slice_is_harmful(player_index: int, slice: Dictionary) -> bool:
	match slice["effect"]:
		"gold":
			return int(slice["amount"]) < 0 and int(players[player_index]["gold"]) > 0
		"to_shadow":
			return true
	return false


# If the player has the right protective passive running, spend a charge, say so
# and return true: the harm must then NOT happen.
func _try_block(player_index: int, source: String, what: String) -> bool:
	var guard := _guard_item(source)
	if active_effect(player_index, guard).is_empty():
		return false
	var player: Dictionary = players[player_index]
	message.emit("%s's %s blocks %s!" % [player["name"], ItemData.find(guard)["name"], what])
	_spend_protection_charge(player_index, guard)
	return true


func _spend_protection_charge(player_index: int, item_id: String) -> void:
	var effect := active_effect(player_index, item_id)
	if effect.is_empty():
		return
	effect["charges"] = int(effect["charges"]) - 1
	var name: String = ItemData.find(item_id)["name"]
	var who: String = players[player_index]["name"]
	if int(effect["charges"]) <= 0:
		_remove_active(player_index, item_id)
		message.emit("%s's %s is used up." % [who, name])
	else:
		message.emit("%s's %s has %s left." % [who, name,
			ItemData.charge_text(int(effect["charges"]), ItemData.find(item_id)["unit"])])


## Answer the yes/no question that is waiting in `pending`. For the Teleport
## question: true = use the Anchor to stay put, false = get teleported.
func resolve_choice(accept: bool) -> bool:
	if pending.get("kind", "") != "choice":
		return false
	var player_index: int = pending["player"]
	var choice: String = pending["choice"]
	pending = {}
	match choice:
		"anchor_teleport":
			if accept and not active_effect(player_index, "anchor").is_empty():
				message.emit("%s's Anchor holds - %s stays put!" % [
					players[player_index]["name"], players[player_index]["name"]])
				_spend_protection_charge(player_index, "anchor")
			else:
				_teleport(player_index)
	_advance_pending()
	changed.emit()
	return true


# ---------------------------------------------------------------------------
# Hand and passive-item helpers
# ---------------------------------------------------------------------------

# Move one extra move or the normal move: uses up whichever is available.
func _consume_move() -> void:
	if has_moved:
		extra_moves = maxi(0, extra_moves - 1)
	has_moved = true


func _remove_from_hand(player_index: int, item_id: String) -> void:
	var hand: Array = players[player_index]["hand"]
	for i in hand.size():
		if hand[i]["id"] == item_id:
			hand.remove_at(i)
			return


func _remove_active(player_index: int, item_id: String) -> void:
	var active: Array = players[player_index]["active"]
	for i in active.size():
		if active[i]["id"] == item_id:
			active.remove_at(i)
			return


# Gold Rush doubles gold from the turn AFTER the one it was activated on.
func _gold_rush_running(player_index: int) -> bool:
	var effect := active_effect(player_index, "gold_rush")
	return not effect.is_empty() and not effect["fresh"]


# Prospector's Pick: +1 gold on each Neutral landing while it has charges.
func _prospectors_pick_bonus(player_index: int) -> void:
	var effect := active_effect(player_index, "prospectors_pick")
	if effect.is_empty():
		return
	var player: Dictionary = players[player_index]
	var gained := _add_gold(player_index, 1, "pick")
	effect["charges"] = int(effect["charges"]) - 1
	message.emit("%s's Prospector's Pick finds %d gold." % [player["name"], gained])
	if int(effect["charges"]) <= 0:
		_remove_active(player_index, "prospectors_pick")
		message.emit("%s's Prospector's Pick is used up." % player["name"])


# End of a full round: sold-out items count down, and one copy comes back at 0
# (never more than the item's starting stock). Items that aren't sold out never restock.
func _tick_shop_restocks() -> void:
	for shop in shops.values():
		var timers: Dictionary = shop["restock"]
		for item_id in timers.keys():
			timers[item_id] = int(timers[item_id]) - 1
			if int(timers[item_id]) <= 0:
				shop["stock"][item_id] = mini(1, ItemData.start_stock(item_id))
				timers.erase(item_id)


# Called when a player's turn ends: passives measured in turns count down.
# The turn a passive was activated on doesn't count.
func _tick_turn_effects(player_index: int) -> void:
	var player: Dictionary = players[player_index]
	var remaining: Array = []
	for effect in player["active"]:
		if ItemData.find(effect["id"]).get("unit", "") == "turns":
			if effect["fresh"]:
				effect["fresh"] = false
			else:
				effect["charges"] = int(effect["charges"]) - 1
			if int(effect["charges"]) <= 0:
				message.emit("%s's %s has run out." % [
					player["name"], ItemData.find(effect["id"])["name"]])
				continue
		remaining.append(effect)
	player["active"] = remaining


# ---------------------------------------------------------------------------
# Shadow Realm
# ---------------------------------------------------------------------------

func _shadow_space_id() -> int:
	for space in spaces:
		if space["type"] == "Shadow Realm":
			return space["id"]
	return start_id


# Trap a player. If it is their own turn they spin straight away.
func _trap(player_index: int) -> void:
	var player: Dictionary = players[player_index]
	player["trapped"] = true
	player["shadow_spins"] = 0   # being sent/landing here does not count as a spin
	# Whatever the old space had in store for this player no longer applies.
	pending_queue = pending_queue.filter(func(entry: Dictionary) -> bool:
		return int(entry.get("player", current_player)) != player_index)
	if player_index == current_player:
		_queue_pending({"kind": "wheel", "wheel": "shadow"})


# Beginning of a turn: a trapped player must spin before anything else.
func _begin_turn() -> void:
	var player := current()
	_resolve_curses(current_player)
	if player["skip_move"]:
		player["skip_move"] = false
		has_moved = true
		message.emit("%s is stuck in the mud and loses their move." % player["name"])
	if player["trapped"]:
		message.emit("%s is in the Shadow Realm and must spin." % player["name"])
		_queue_pending({"kind": "wheel", "wheel": "shadow"})


# If every player is trapped AND every one of them has really spun during this
# stay, everyone is released to Start. This is only ever checked right after a
# spin, so being invited in (0 spins) or a turn merely starting can't trigger it.
func _check_mass_escape() -> void:
	for player in players:
		if not player["trapped"] or int(player["shadow_spins"]) < 1:
			return
	for player in players:
		player["trapped"] = false
		player["shadow_spins"] = 0
		player["position"] = start_id
	discovered[start_id] = true
	message.emit("All players were trapped and have spun - everyone is released to Start!")


# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

## Compass direction from one space to another (works for any distance).
static func direction_between(a: int, b: int) -> String:
	var dr: int = floori(b / float(GRID_SIZE)) - floori(a / float(GRID_SIZE))
	var dc: int = (b % GRID_SIZE) - (a % GRID_SIZE)
	var ns := ""
	if dr < 0:
		ns = "North"
	elif dr > 0:
		ns = "South"
	var ew := ""
	if dc < 0:
		ew = "West"
	elif dc > 0:
		ew = "East"
	return ns + ew


## How many grid steps apart two spaces are, counting diagonals as one step.
static func distance(a: int, b: int) -> int:
	var dr := absi(floori(a / float(GRID_SIZE)) - floori(b / float(GRID_SIZE)))
	var dc := absi((a % GRID_SIZE) - (b % GRID_SIZE))
	return maxi(dr, dc)


## How many connection steps from `origin` to every reachable space
## ({space id: steps}). A long-distance link counts as one step.
func steps_from(origin: int) -> Dictionary:
	var steps := {origin: 0}
	var queue: Array = [origin]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next_id in spaces[current]["connections"]:
			if not steps.has(next_id):
				steps[next_id] = int(steps[current]) + 1
				queue.append(next_id)
	return steps


## Turns the master seed into a separate seed for each random stream. Uses a
## simple fixed formula (not Godot's hash()) so the same seed gives the same
## game on every device and every future Godot version.
static func derive_seed(master_seed: int, stream_name: String) -> int:
	var hash_value := 2166136261
	for byte in ("%d:%s" % [master_seed, stream_name]).to_utf8_buffer():
		hash_value = ((hash_value ^ int(byte)) * 16777619) & 0xFFFFFFFF
	return hash_value


## The space next to `from` in a compass direction, or -1 at the edge of the board.
static func neighbor_in_direction(from: int, direction: String) -> int:
	if not DIRECTION_OFFSETS.has(direction):
		return -1
	var offset: Vector2i = DIRECTION_OFFSETS[direction]
	var row := floori(from / float(GRID_SIZE)) + offset.x
	var col := (from % GRID_SIZE) + offset.y
	if row < 0 or row >= GRID_SIZE or col < 0 or col >= GRID_SIZE:
		return -1
	return row * GRID_SIZE + col
