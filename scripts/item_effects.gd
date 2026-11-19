class_name ItemEffects
extends RefCounted
## What each item DOES. GameState calls problem() to ask "can this be used right
## now?" and use() to carry it out. To build a new item, add a case to both
## (problem() only if it has extra requirements) and set implemented to true in
## item_data.gd.
##
## Gold amounts for the interference items.
const SNARE_GOLD := 2        # Thief's Snare: taken from whoever lands on it
const COIN_GOLD := 1         # Cursed Coin: lost, then the Bad wheel spins
const CURSE_GOLD := 2        # Misfortune Curse: lost at the start of the victim's next turn
const PICKPOCKET_GOLD := 1
const HEIST_GOLD := 3
const BOUNTY_GOLD := 2       # Bounty Drop: gold placed...
const BOUNTY_RANGE := 2      # ...within this many steps of the chosen opponent

## Information items send their answer privately to the player who used them
## (GameState.private_message); everyone else only sees that the item was used.


## "" if the current player can use this item right now, otherwise why not.
## (The general rules - your turn, no wheel waiting, not trapped, holding it - are
## checked by GameState before this is called.)
static func problem(state: GameState, item_id: String, params: Dictionary) -> String:
	var position: int = state.current()["position"]
	match item_id:
		"homing_charm":
			if position == state.start_id:
				return "You are already at Start."
		"blink_stone":
			if blink_options(state).is_empty():
				return "There is nowhere to blink to."
		"spyglass":
			if spyglass_options(state).is_empty():
				return "There are no hidden spaces to look at."
		"wind_step":
			if state.extra_moves > 0:
				return "You already have an extra move."
		"skeleton_key":
			if not state.has_move_available():
				return "You need a move available to use the Skeleton Key."
			if not GameState.DIRECTION_OFFSETS.has(str(params.get("direction", ""))):
				return "Choose a direction first."
		"thiefs_snare", "mud_trap", "cursed_coin":
			var type_name := state.space_type(position)
			if type_name == "Start" or type_name == "Shadow Realm":
				return "Traps can't be set on Start or the Shadow Realm."
		"pickpocket", "close_quarters_heist", "misfortune_curse", "distraction_bell", "bounty_drop":
			var options := target_options(state, item_id)
			if options.is_empty():
				if item_id == "misfortune_curse":
					return "No opponent has any gold to lose."
				if item_id == "bounty_drop":
					return "No free opponent to place gold near."
				return "No opponent sharing your space has any gold."
			if params.has("target"):
				if not options.has(int(params["target"])):
					return "That isn't a valid target."
			elif options.size() > 1:
				return "Choose a target first."
			if item_id == "bounty_drop":
				var chosen: int = int(params["target"]) if params.has("target") else options[0]
				if bounty_options(state, chosen).is_empty():
					return "There is no space near them to put the gold on."
	return ""


static func use(state: GameState, player_index: int, item_id: String, params: Dictionary) -> void:
	var player: Dictionary = state.players[player_index]
	var who: String = player["name"]
	var position: int = player["position"]

	match item_id:
		"scout_lens":
			var targets: Array = state.spaces[position]["connections"].duplicate()
			targets.sort_custom(func(a: int, b: int) -> bool:
				return GameState.DIRECTIONS.find(GameState.direction_between(position, a)) \
					< GameState.DIRECTIONS.find(GameState.direction_between(position, b)))
			var lines: Array = []
			for target in targets:
				lines.append("%s: %s" % [GameState.direction_between(position, target), state.space_type(target)])
			state.private_message.emit(player_index,
				"Scout Lens - the spaces connected to yours:\n" + "\n".join(lines))

		"danger_bell":
			var danger := false
			for target in state.spaces[position]["connections"]:
				var type_name := state.space_type(target)
				if type_name == "Bad" or type_name == "Shadow Realm":
					danger = true
			state.private_message.emit(player_index, "Danger Bell - " + (
				"yes, at least one connected space is Bad or the Shadow Realm." if danger
				else "no, none of the connected spaces are Bad or the Shadow Realm."))

		"crown_whisper":
			var steps := state.walking_steps_to(state.crown_id())
			if steps.has(position):
				state.private_message.emit(player_index,
					"Crown Whisper - you are %d steps from the Crown." % steps[position])
			else:
				state.private_message.emit(player_index,
					"Crown Whisper - there is no walking route to the Crown from here.")

		"crown_compass":
			var crown := state.crown_id()
			var steps := state.walking_steps_to(crown)
			var exits: Array = []
			if steps.has(position):
				for target in state.spaces[position]["connections"]:
					if steps.has(target) and int(steps[target]) == int(steps[position]) - 1 \
							and (target == crown or state.can_walk_through(target)):
						exits.append(GameState.direction_between(position, target))
			if exits.is_empty():
				state.private_message.emit(player_index,
					"Crown Compass - there is no walking route to the Crown from here.")
			else:
				var exit_name: String = exits[state.rng.randi_range(0, exits.size() - 1)]
				state.private_message.emit(player_index,
					"Crown Compass - the shortest route to the Crown leaves to the %s." % exit_name)

		"spyglass":
			var options := spyglass_options(state)
			var chosen: int = options[state.rng.randi_range(0, options.size() - 1)]
			var steps := state.steps_from(position)
			state.private_message.emit(player_index, "Spyglass - a %s space is %d steps away." % [
				state.space_type(chosen), steps.get(chosen, 0)])

		"wind_step":
			state.extra_moves += 1
			state.message.emit("%s gains an extra move this turn." % who)

		"homing_charm":
			state._land(player_index, state.start_id, "%s " % who, false)

		"blink_stone":
			var options := blink_options(state)
			var destination: int = options[state.rng.randi_range(0, options.size() - 1)]
			state._land(player_index, destination, "%s blinked away and " % who)

		"thiefs_snare", "mud_trap", "cursed_coin":
			state.place_trap(player_index, item_id)
			state.private_message.emit(player_index,
				"%s set on this %s space. It stays hidden until someone lands here." % [
					ItemData.find(item_id)["name"], state.space_type(position)])

		"pickpocket", "close_quarters_heist":
			var targets := target_options(state, item_id)
			var victim: int = int(params["target"]) if params.has("target") else targets[0]
			var amount := PICKPOCKET_GOLD if item_id == "pickpocket" else HEIST_GOLD
			var taken := state.steal_gold(player_index, victim, amount, "the theft")
			if taken > 0:
				state.message.emit("%s steals %d gold from %s!" % [who, taken, state.players[victim]["name"]])

		"misfortune_curse":
			var victims := target_options(state, item_id)
			var chosen_victim: int = int(params["target"]) if params.has("target") else victims[0]
			state.curses.append({"target": chosen_victim, "owner": player_index})
			state.private_message.emit(player_index, "Misfortune Curse - it falls on %s, and strikes at the start of their next turn." % state.players[chosen_victim]["name"])

		"distraction_bell":
			var lured: int = int(params["target"]) if params.has("target") else target_options(state, item_id)[0]
			state.goblin_lure = lured
			state.private_message.emit(player_index,
				"Distraction Bell - the Goblin will head for %s on its next move." % state.players[lured]["name"])

		"bounty_drop":
			var near: int = int(params["target"]) if params.has("target") else target_options(state, item_id)[0]
			var places := bounty_options(state, near)
			var place: int = places[state.rng.randi_range(0, places.size() - 1)]
			state.place_bounty(place, BOUNTY_GOLD)
			state.message.emit("%d gold has been placed near %s." % [BOUNTY_GOLD, state.players[near]["name"]])

		"skeleton_key":
			var direction := str(params["direction"])
			var target := GameState.neighbor_in_direction(position, direction)
			state._consume_move()
			if target < 0 or state.space_type(target) == "Crown":
				# The same message for a board edge and for the Crown, so probing
				# with the Key can't be used to find the Crown.
				state.message.emit("The Skeleton Key finds nothing to open that way.")
			else:
				state._land(player_index, target, "%s unlocked the way %s and " % [who, direction])


## Which players the current player can aim an item at (a list of player indices).
##   Pickpocket / Heist: opponents on your space who are free and have gold.
##   Misfortune Curse: the opponent(s) with the most gold - more than one on a tie.
static func target_options(state: GameState, item_id: String) -> Array:
	var me := state.current_player
	var options: Array = []
	match item_id:
		"pickpocket", "close_quarters_heist":
			for i in state.players.size():
				var other: Dictionary = state.players[i]
				if i != me and other["position"] == state.current()["position"] \
						and not other["trapped"] and int(other["gold"]) > 0:
					options.append(i)
		"distraction_bell":
			for i in state.players.size():
				if i != me:
					options.append(i)
		"bounty_drop":
			for i in state.players.size():
				if i != me and not state.players[i]["trapped"]:
					options.append(i)
		"misfortune_curse":
			var most := 0
			for i in state.players.size():
				if i != me:
					most = maxi(most, int(state.players[i]["gold"]))
			if most > 0:
				for i in state.players.size():
					if i != me and int(state.players[i]["gold"]) == most:
						options.append(i)
	return options


## Where Bounty Drop gold can go near an opponent: within BOUNTY_RANGE steps of
## them (not on their own space), never Start, the Shadow Realm or the Crown.
static func bounty_options(state: GameState, near_player: int) -> Array:
	var steps := state.steps_from(int(state.players[near_player]["position"]))
	var options: Array = []
	for space in state.spaces:
		var id: int = space["id"]
		var distance: int = int(steps.get(id, 99))
		var type_name: String = space["type"]
		if distance >= 1 and distance <= BOUNTY_RANGE \
				and type_name != "Start" and type_name != "Shadow Realm" and type_name != "Crown":
			options.append(id)
	return options


## Spaces Blink Stone can send the current player to: more than 1 step away,
## nobody standing there, never the Crown or a Teleport space.
static func blink_options(state: GameState) -> Array:
	var steps := state.steps_from(int(state.current()["position"]))
	var options: Array = []
	for space in state.spaces:
		var id: int = space["id"]
		if int(steps.get(id, 99)) > 1 and state.players_on(id).is_empty() \
				and space["type"] != "Crown" and space["type"] != "Teleport":
			options.append(id)
	return options


## Spaces Spyglass can look at: hidden (nobody standing there) and not the Crown.
static func spyglass_options(state: GameState) -> Array:
	var options: Array = []
	for space in state.spaces:
		var id: int = space["id"]
		if state.players_on(id).is_empty() and space["type"] != "Crown":
			options.append(id)
	return options
