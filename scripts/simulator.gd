class_name Simulator
extends RefCounted
## Plays whole games with simple bots so rule changes can be measured instead of
## guessed. Change the wheels, the Crown cost or the Start bonus, run it again,
## and compare the numbers.
##
## Bots:
##   RANDOM   - picks a random legal move every turn (a floor for how well players play).
##   INFORMED - knows the whole map: farms the nearest Good space, avoids Bad and
##              Shadow Realm spaces, and heads straight for the Crown once it has
##              enough gold (about the fastest a very good player could go).
## Real games land somewhere between the two.

enum Bot { RANDOM, INFORMED }

const MAX_ROUNDS := 300
const SEAT_NAMES := ["Seat 1", "Seat 2", "Seat 3"]


## Plays `games` games and returns a summary Dictionary (see format_report).
static func run_batch(games: int, bot: Bot, first_seed: int = 1, max_rounds: int = MAX_ROUNDS) -> Dictionary:
	var rounds_list: Array = []
	var wins_by_seat := [0, 0, 0]
	var unfinished := 0
	var totals := {"gold_gained": {}, "gold_lost": {}, "landings": {}, "shadow_spins": 0, "turns": 0}

	for n in games:
		var result := play_game(first_seed + n, bot, max_rounds)
		if int(result["winner"]) >= 0:
			rounds_list.append(result["rounds"])
			wins_by_seat[result["winner"]] += 1
		else:
			unfinished += 1
		_merge_stats(totals, result["stats"])

	rounds_list.sort()
	var finished := rounds_list.size()
	var summary := {
		"bot": "INFORMED" if bot == Bot.INFORMED else "RANDOM",
		"games": games,
		"finished": finished,
		"unfinished": unfinished,
		"max_rounds": max_rounds,
		"wins_by_seat": wins_by_seat,
		"totals": totals,
	}
	if finished > 0:
		var sum := 0
		for r in rounds_list:
			sum += int(r)
		summary["rounds_min"] = rounds_list[0]
		summary["rounds_median"] = rounds_list[finished / 2]
		summary["rounds_p90"] = rounds_list[mini(finished - 1, int(finished * 0.9))]
		summary["rounds_mean"] = float(sum) / finished
	return summary


## Plays one game with all three seats controlled by the same kind of bot.
static func play_game(seed_value: int, bot: Bot, max_rounds: int = MAX_ROUNDS) -> Dictionary:
	var state := GameState.new()
	state.setup(SEAT_NAMES, 12, seed_value)
	var bot_rng := RandomNumberGenerator.new()
	bot_rng.seed = GameState.derive_seed(seed_value, "bots")

	var crown_id := -1
	var good_ids: Array = []
	for space in state.spaces:
		if space["type"] == "Crown":
			crown_id = space["id"]
		elif space["type"] == "Good":
			good_ids.append(space["id"])
	var maps := {
		"crown_dist": _distances_from(state.spaces, [crown_id]),
		"good_dist": _distances_from(state.spaces, good_ids),
	}

	var action_budget := max_rounds * 3 * 6   # safety net against a stuck game
	while state.winner < 0 and state.round_number <= max_rounds and action_budget > 0:
		action_budget -= 1
		if not state.pending.is_empty():
			state.spin()
		elif not state.legal_moves().is_empty():
			state.move(_choose_direction(state, bot, bot_rng, maps))
		else:
			state.end_turn()

	return {"winner": state.winner, "rounds": state.round_number, "stats": state.stats}


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

## Expected payouts of the wheels in wheel_data.gd, worked out exactly.
static func wheel_report() -> String:
	var lines: Array = ["=== Wheel math (from wheel_data.gd) ==="]
	for wheel_name in ["good", "bad"]:
		var slices := WheelData.get_wheel(wheel_name)
		var gold := 0
		var shadow := 0
		for slice in slices:
			if slice["effect"] == "gold":
				gold += int(slice["amount"])
			elif slice["effect"] == "to_shadow":
				shadow += 1
		lines.append("%s wheel: %d slices, average gold per spin %+.2f, Shadow Realm chance %.0f%%" % [
			wheel_name.capitalize(), slices.size(), float(gold) / slices.size(),
			100.0 * shadow / slices.size()])

	var still_trapped := 1.0
	var expected_spins := 0.0
	for k in 40:
		var slices := WheelData.shadow(k)
		var escape := 0
		for slice in slices:
			if slice["effect"] == "return_home":
				escape += 1
		expected_spins += still_trapped
		still_trapped *= 1.0 - float(escape) / slices.size()
	lines.append("Shadow wheel: on average %.1f spins to escape (first spin %.0f%% chance)" % [
		expected_spins, 100.0 * _escape_chance(0)])
	return "\n".join(lines)


static func format_report(summary: Dictionary) -> String:
	var games: int = summary["games"]
	var lines: Array = []
	lines.append("=== %s bots, %d games (Crown costs %d gold) ===" % [
		summary["bot"], games, GameState.CROWN_GOLD_REQUIRED])
	lines.append("Finished within %d rounds: %d of %d (%.0f%%)" % [
		summary["max_rounds"], summary["finished"], games, 100.0 * int(summary["finished"]) / games])
	if int(summary["finished"]) > 0:
		lines.append("Rounds to win: median %d, average %.1f, fastest %d, 90th percentile %d" % [
			summary["rounds_median"], summary["rounds_mean"], summary["rounds_min"], summary["rounds_p90"]])
		var wins: Array = summary["wins_by_seat"]
		var win_text: Array = []
		for i in wins.size():
			win_text.append("%s %.0f%%" % [SEAT_NAMES[i], 100.0 * int(wins[i]) / int(summary["finished"])])
		lines.append("Who wins (by turn order): " + ", ".join(win_text))

	var totals: Dictionary = summary["totals"]
	lines.append("Per game, all players together:")
	lines.append("  gold gained: " + _per_game(totals["gold_gained"], games, "+"))
	lines.append("  gold lost:   " + _per_game(totals["gold_lost"], games, "-"))
	lines.append("  Shadow wheel spins: %.1f" % (float(totals["shadow_spins"]) / games))
	lines.append("  landings: " + _per_game(totals["landings"], games, ""))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Bot brains and helpers
# ---------------------------------------------------------------------------

static func _choose_direction(state: GameState, bot: Bot, rng: RandomNumberGenerator, maps: Dictionary) -> String:
	var moves := state.legal_moves()
	var directions: Array = moves.keys()
	if bot == Bot.RANDOM:
		return directions[rng.randi_range(0, directions.size() - 1)]

	# INFORMED: head for the Crown with enough gold, otherwise for the nearest Good space.
	var wants_crown: bool = int(state.current()["gold"]) >= GameState.CROWN_GOLD_REQUIRED
	var distances: Dictionary = maps["crown_dist"] if wants_crown else maps["good_dist"]
	var best: Array = []
	var best_score := 1000000.0
	for direction in directions:
		var target: int = moves[direction]
		var score := float(distances.get(target, 99))
		var type_name := state.space_type(target)
		if type_name == "Shadow Realm" or type_name == "Teleport":
			score += 50.0   # landing here ends the trip: avoid unless there is no choice
		elif type_name == "Bad":
			score += 0.5    # only a tie-breaker, so a Bad space on the only route is still taken
		if score < best_score:
			best_score = score
			best = [direction]
		elif score == best_score:
			best.append(direction)
	return best[rng.randi_range(0, best.size() - 1)]


# Walking steps from every space to the nearest of `targets`. Shadow Realm and
# Teleport spaces are dead ends (you can't walk on from them), so routes never
# pass through them.
static func _distances_from(spaces: Array, targets: Array) -> Dictionary:
	var dist := {}
	var queue: Array = []
	for target in targets:
		dist[target] = 0
		queue.append(target)
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var type_name: String = spaces[current]["type"]
		if type_name == "Shadow Realm" or type_name == "Teleport":
			continue
		for next_id in spaces[current]["connections"]:
			if not dist.has(next_id):
				dist[next_id] = int(dist[current]) + 1
				queue.append(next_id)
	return dist


static func _escape_chance(spins_so_far: int) -> float:
	var slices := WheelData.shadow(spins_so_far)
	var escape := 0
	for slice in slices:
		if slice["effect"] == "return_home":
			escape += 1
	return float(escape) / slices.size()


static func _merge_stats(totals: Dictionary, stats: Dictionary) -> void:
	for group in ["gold_gained", "gold_lost", "landings"]:
		var into: Dictionary = totals[group]
		var from: Dictionary = stats[group]
		for key in from:
			into[key] = int(into.get(key, 0)) + int(from[key])
	totals["shadow_spins"] = int(totals["shadow_spins"]) + int(stats["shadow_spins"])
	totals["turns"] = int(totals["turns"]) + int(stats["turns"])


static func _per_game(counters: Dictionary, games: int, sign: String) -> String:
	var parts: Array = []
	var keys: Array = counters.keys()
	keys.sort()
	for key in keys:
		parts.append("%s %s%.1f" % [key, sign, float(counters[key]) / games])
	return ", ".join(parts) if not parts.is_empty() else "none"
