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
##   state.end_turn()

signal changed                 # anything changed -> refresh the views
signal message(text: String)   # something worth telling the players
signal wheel_spun(wheel_name: String, slices: Array, index: int)

const GRID_SIZE := 5
const CROWN_GOLD_REQUIRED := 10      # gold needed (and paid) to win at the Crown
const START_GOLD_BONUS := 1          # gold for landing on the Start space...
const START_BONUS_GOLD_LIMIT := 3    # ...but only if you have FEWER than this much gold

## Memory Mode (default): a space is face-up only while a player stands on it.
## Turn it off and spaces stay face-up once they have been visited.
var memory_mode := true

var spaces: Array = []   # from GridGenerator: {"id", "type", "connections"}
var players: Array = []  # see setup() for the fields
var current_player := 0
var round_number := 1
var has_moved := false   # has the current player used their move/spin this turn?
var discovered := {}     # space id -> true, for when Memory Mode is off
var pending := {}        # {"kind": "wheel", "wheel": "good"|"bad"|"shadow"} or {}
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
	stats = {"gold_gained": {}, "gold_lost": {}, "landings": {}, "shadow_spins": 0, "turns": 0}

	players.clear()
	for player_name in player_names:
		players.append({
			"name": str(player_name),
			"position": start_id,
			"gold": 0,
			"trapped": false,     # in the Shadow Realm
			"shadow_spins": 0,    # real spins during the CURRENT stay (not counting being sent)
			"inventory": {},      # item id -> how many held
			"purchases": {},      # item id -> total bought (for purchase limits)
		})
	current_player = 0
	round_number = 1
	has_moved = false
	pending = {}
	winner = -1
	discovered = {start_id: true}
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
	if winner >= 0 or has_moved or not pending.is_empty() or current()["trapped"]:
		return result
	var from: int = current()["position"]
	for target in spaces[from]["connections"]:
		var direction := direction_between(from, target)
		if not result.has(direction) or distance(from, target) < distance(from, result[direction]):
			result[direction] = target
	return result


func can_end_turn() -> bool:
	if winner >= 0 or not pending.is_empty():
		return false
	return has_moved or legal_moves().is_empty()


## The slices of the wheel that is waiting to be spun ([] if none).
func pending_slices() -> Array:
	if pending.get("kind", "") != "wheel":
		return []
	return WheelData.get_wheel(pending["wheel"], current()["shadow_spins"])


func can_shop() -> bool:
	return winner < 0 and pending.is_empty() and not current()["trapped"] \
		and space_type(current()["position"]) == "Shop"


## "" if the current player can buy this item right now, otherwise why not.
func buy_problem(item_id: String) -> String:
	var item := ItemData.find(item_id)
	if item.is_empty():
		return "Unknown item."
	if not can_shop():
		return "You must be on a Shop space."
	var player := current()
	if int(player["gold"]) < int(item["cost"]):
		return "Not enough gold."
	var limit: int = item["max"]
	if limit >= 0 and int(player["purchases"].get(item_id, 0)) >= limit:
		return "Purchase limit reached."
	return ""


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func move(direction: String) -> bool:
	var moves := legal_moves()
	if not moves.has(direction):
		return false
	has_moved = true
	_land(current_player, moves[direction], "%s moved %s and " % [current()["name"], direction])
	changed.emit()
	return true


## Spin the wheel that is waiting (Good, Bad or Shadow) for the current player.
func spin() -> bool:
	if pending.get("kind", "") != "wheel":
		return false
	var wheel_name: String = pending["wheel"]
	var slices := pending_slices()
	var index := rng.randi_range(0, slices.size() - 1)
	var slice: Dictionary = slices[index]

	pending = {}
	has_moved = true   # spinning uses up the turn's move/spin
	if wheel_name == "shadow":
		current()["shadow_spins"] = int(current()["shadow_spins"]) + 1
		stats["shadow_spins"] = int(stats["shadow_spins"]) + 1

	wheel_spun.emit(wheel_name, slices, index)
	_apply_slice(current_player, slice, wheel_name)
	changed.emit()
	return true


func buy(item_id: String) -> bool:
	if buy_problem(item_id) != "":
		return false
	var item := ItemData.find(item_id)
	var player := current()
	player["gold"] = int(player["gold"]) - int(item["cost"])
	player["inventory"][item_id] = int(player["inventory"].get(item_id, 0)) + 1
	player["purchases"][item_id] = int(player["purchases"].get(item_id, 0)) + 1
	message.emit("%s bought %s for %d gold." % [player["name"], item["name"], item["cost"]])
	changed.emit()
	return true


func end_turn() -> bool:
	if not can_end_turn():
		return false
	stats["turns"] = int(stats["turns"]) + 1
	current_player = (current_player + 1) % players.size()
	if current_player == 0:
		round_number += 1
	has_moved = false
	message.emit("%s's turn." % current()["name"])
	_begin_turn()
	changed.emit()
	return true


# ---------------------------------------------------------------------------
# Space effects
# ---------------------------------------------------------------------------

# Put a player on a space and trigger that space's effect.
# `prefix` is the start of the log sentence, e.g. "Alice moved West and ".
func _land(player_index: int, target: int, prefix: String) -> void:
	var player: Dictionary = players[player_index]
	player["position"] = target
	discovered[target] = true

	var type_name := space_type(target)
	_count("landings", type_name, 1)
	var named := type_name == "Start" or type_name == "Crown"
	message.emit("%slanded on %s %s%s." % [
		prefix, "the" if named else "a", type_name, "" if named else " space"])

	match type_name:
		"Start":
			if int(player["gold"]) < START_BONUS_GOLD_LIMIT:
				var gained := _add_gold(player_index, START_GOLD_BONUS, "start")
				message.emit("%s gains %d gold from Start." % [player["name"], gained])
			else:
				message.emit("%s has %d gold or more, so Start gives no bonus." % [
					player["name"], START_BONUS_GOLD_LIMIT])
		"Good":
			pending = {"kind": "wheel", "wheel": "good"}
		"Bad":
			pending = {"kind": "wheel", "wheel": "bad"}
		"Teleport":
			_teleport(player_index)
		"Shadow Realm":
			message.emit("%s is trapped in the Shadow Realm!" % player["name"])
			_trap(player_index)
		"Crown":
			_check_crown(player_index)
		"Shop":
			message.emit("%s can shop here." % player["name"])
		"Combat":
			message.emit("Combat isn't built yet - nothing happens.")


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
	var before: int = player["gold"]
	player["gold"] = maxi(0, before + amount)
	var change: int = int(player["gold"]) - before
	if change > 0:
		_count("gold_gained", source, change)
	elif change < 0:
		_count("gold_lost", source, -change)
	return change


func _count(group: String, key: String, amount: int) -> void:
	var counters: Dictionary = stats[group]
	counters[key] = int(counters.get(key, 0)) + amount


# What a wheel slice does.
func _apply_slice(player_index: int, slice: Dictionary, wheel_name: String) -> void:
	var player: Dictionary = players[player_index]
	var who: String = player["name"]
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
	if player_index == current_player:
		pending = {"kind": "wheel", "wheel": "shadow"}


# Beginning of a turn: a trapped player must spin before anything else.
func _begin_turn() -> void:
	if current()["trapped"]:
		message.emit("%s is in the Shadow Realm and must spin." % current()["name"])
		pending = {"kind": "wheel", "wheel": "shadow"}


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
