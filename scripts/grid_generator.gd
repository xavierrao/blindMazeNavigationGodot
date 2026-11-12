class_name GridGenerator
extends RefCounted
## Procedural map generator for Blind Crown Quest (GDScript port of grid_generator.py).
##
## Usage:
##   var gen := GridGenerator.new()
##   var spaces: Array = gen.create_grid(12)          # random map, start on space 12
##   var spaces2: Array = gen.create_grid(12, 12345)  # same seed -> same map
##
## Each space is a Dictionary: {"id": int, "type": String, "connections": Array[int]}
## Returns an empty Array (and logs an error) if no valid map could be built.

const SIZE := 5
const SPACE_COUNT := SIZE * SIZE
const MAX_CONNECTIONS := 4
const MAX_ATTEMPTS := 200
const MIN_STEPS_TO_CROWN := 3
const NON_ADJACENT_CHANCE := 0.05
const CARDINAL_CHANCE := 0.5

# Border spaces of the 5x5 grid.
const OUTSIDE := [0, 1, 2, 3, 4, 5, 9, 10, 14, 15, 19, 20, 21, 22, 23, 24]
const ORDINALS := ["NorthWest", "NorthEast", "SouthWest", "SouthEast"]
# Steps are (row_change, col_change).
const CARDINAL_STEPS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const DIAGONAL_STEPS := [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]
# The Start space is added separately; these are the unique special spaces.
const SPECIAL_TYPES := [
	"Crown", "Shadow Realm", "Teleport",
	"Combat", "Combat",
	"Good", "Good", "Good",
	"Bad", "Bad", "Bad",
	"Shop", "Shop", "Shop",
]

var rng := RandomNumberGenerator.new()
var spaces: Array = []
var crown_id := -1
var start_id := 12


func create_grid(start_space_id: int = 12, seed_value: int = -1) -> Array:
	start_id = start_space_id
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	_assign_types()

	# The original Python made one first attempt, then up to 200 retries.
	for _attempt in MAX_ATTEMPTS + 1:
		_clear_connections()
		_connect_outside_cardinals()  # Phase 1
		_connect_non_adjacent()       # Phase 2
		_connect_cardinals()          # Phase 3
		_remove_inner_diagonals()     # Phase 4
		_connect_crown()              # Phase 5
		_connect_unvisited()          # Fallback
		if _is_valid():
			return spaces

	push_error("Failed to generate valid grid after %d attempts" % MAX_ATTEMPTS)
	return []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _assign_types() -> void:
	spaces.clear()
	for i in SPACE_COUNT:
		spaces.append({"id": i, "type": "Neutral", "connections": []})
	spaces[start_id]["type"] = "Start"

	var available: Array = []
	for i in SPACE_COUNT:
		if i != start_id:
			available.append(i)
	_shuffle(available)

	for i in SPECIAL_TYPES.size():
		var space_id: int = available[i]
		spaces[space_id]["type"] = SPECIAL_TYPES[i]
		if SPECIAL_TYPES[i] == "Crown":
			crown_id = space_id


func _clear_connections() -> void:
	for s in spaces:
		s["connections"] = []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Fisher-Yates shuffle using our own RNG so seeds are reproducible.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _row(id: int) -> int:
	return floori(id / float(SIZE))


func _col(id: int) -> int:
	return id % SIZE


func _conns(id: int) -> Array:
	return spaces[id]["connections"]


func _link(a: int, b: int) -> void:
	if not _conns(a).has(b):
		_conns(a).append(b)
	if not _conns(b).has(a):
		_conns(b).append(a)


func _unlink(a: int, b: int) -> void:
	_conns(a).erase(b)
	_conns(b).erase(a)


# Direction from one space to another. Returns "" for spaces in the same row or
# column (the Python version treated those as having no direction, so the
# cardinal branches it contained were unreachable and are dropped here).
func _direction(from_id: int, to_id: int) -> String:
	var dr: int = _row(to_id) - _row(from_id)
	var dc: int = _col(to_id) - _col(from_id)
	if dr == 0 or dc == 0:
		return ""
	var ns := "North" if dr < 0 else "South"
	var ew := "West" if dc < 0 else "East"
	return ns + ew


func _has_connection_in_direction(id: int, direction: String) -> bool:
	for conn in _conns(id):
		if _direction(id, conn) == direction:
			return true
	return false


func _neighbors(id: int, steps: Array) -> Array:
	var result: Array = []
	var r := _row(id)
	var c := _col(id)
	for step in steps:
		var nr: int = r + step.x
		var nc: int = c + step.y
		if nr >= 0 and nr < SIZE and nc >= 0 and nc < SIZE:
			result.append(nr * SIZE + nc)
	return result


func _reachable_from(start: int) -> Dictionary:
	var visited := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for nxt in _conns(current):
			if not visited.has(nxt):
				visited[nxt] = true
				queue.append(nxt)
	return visited


# Number of steps on the shortest path, or -1 if there is no path.
func _shortest_steps(from_id: int, to_id: int) -> int:
	var dist := {from_id: 0}
	var queue: Array = [from_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == to_id:
			return dist[current]
		for nxt in _conns(current):
			if not dist.has(nxt):
				dist[nxt] = dist[current] + 1
				queue.append(nxt)
	return -1


# Shadow Realm and Teleport spaces can be landed on but never walked through:
# one traps you, the other throws you somewhere else. So the Crown must be
# reachable from Start without stepping on either of them along the way.
func _walkable_steps_to_crown() -> int:
	var dist := {start_id: 0}
	var queue: Array = [start_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var type_name: String = spaces[current]["type"]
		if current != start_id and (type_name == "Shadow Realm" or type_name == "Teleport"):
			continue
		for next_id in _conns(current):
			if not dist.has(next_id):
				dist[next_id] = int(dist[current]) + 1
				queue.append(next_id)
	return int(dist.get(crown_id, -1))


func _can_walk_on_from(id: int) -> bool:
	var type_name: String = spaces[id]["type"]
	return type_name != "Shadow Realm" and type_name != "Teleport"


func _is_valid() -> bool:
	if _reachable_from(start_id).size() != SPACE_COUNT:
		return false
	if _shortest_steps(start_id, crown_id) < MIN_STEPS_TO_CROWN:
		return false
	if _walkable_steps_to_crown() < MIN_STEPS_TO_CROWN:
		return false
	var incoming := 0
	for s in spaces:
		if s["connections"].has(crown_id):
			incoming += 1
	return incoming == 1


# ---------------------------------------------------------------------------
# Generation phases
# ---------------------------------------------------------------------------

# Phase 1: link every border space to its border neighbours (up/down/left/right).
func _connect_outside_cardinals() -> void:
	for id in OUTSIDE:
		if id == crown_id:
			continue
		for adj in _neighbors(id, CARDINAL_STEPS):
			if OUTSIDE.has(adj) and adj != crown_id:
				_link(id, adj)


# Phase 2: rare (5%) long-distance diagonal links, at most one per direction.
func _connect_non_adjacent() -> void:
	for id in SPACE_COUNT:
		if id == crown_id:
			continue

		var groups := {}
		for d in ORDINALS:
			groups[d] = []
		for target in SPACE_COUNT:
			if target == id or target == crown_id:
				continue
			var dr: int = _row(target) - _row(id)
			var dc: int = _col(target) - _col(id)
			if dr == 0 or dc == 0:
				continue
			if absi(dr) <= 1 and absi(dc) <= 1:
				continue  # diagonal neighbour, not a long-distance link
			groups[_direction(id, target)].append(target)

		for d in ORDINALS:
			var targets: Array = groups[d]
			_shuffle(targets)
			for target in targets:
				if _conns(id).size() >= MAX_CONNECTIONS or _conns(target).size() >= MAX_CONNECTIONS:
					continue
				var inverse := _direction(target, id)
				# Both ends must have a free slot in that direction, so no space ever
				# has two exits pointing the same way.
				if inverse != "" and not _has_connection_in_direction(target, inverse) \
						and not _has_connection_in_direction(id, d):
					if rng.randf() < NON_ADJACENT_CHANCE:
						_link(id, target)
						break  # one link per direction


# Phase 3: 50% chance for each up/down/left/right link.
func _connect_cardinals() -> void:
	for id in SPACE_COUNT:
		if id == crown_id:
			continue
		var adjacent := _neighbors(id, CARDINAL_STEPS)
		_shuffle(adjacent)
		for adj in adjacent:
			if _conns(id).size() >= MAX_CONNECTIONS or _conns(adj).size() >= MAX_CONNECTIONS:
				continue
			if adj == crown_id:
				continue
			if rng.randf() < CARDINAL_CHANCE and not _conns(id).has(adj):
				_link(id, adj)


# Phase 4: inner spaces never keep diagonal-neighbour links.
func _remove_inner_diagonals() -> void:
	for id in SPACE_COUNT:
		if OUTSIDE.has(id) or id == crown_id:
			continue
		for adj in _neighbors(id, DIAGONAL_STEPS):
			_unlink(id, adj)


# Phase 5: the Crown gets exactly one connection.
func _connect_crown() -> void:
	var candidates: Array = []
	for id in SPACE_COUNT:
		if id == crown_id:
			continue
		var dir := _direction(id, crown_id)
		if dir != "" and not _has_connection_in_direction(id, dir) \
				and _conns(id).size() < MAX_CONNECTIONS and _can_walk_on_from(id):
			candidates.append(id)

	if not candidates.is_empty():
		var chosen: int = candidates[rng.randi_range(0, candidates.size() - 1)]
		_link(chosen, crown_id)
		return

	# Fallback: pick any space with a direction to the Crown, dropping its
	# existing link in that direction to make room.
	var all_spaces: Array = []
	for id in SPACE_COUNT:
		if id != crown_id:
			all_spaces.append(id)
	_shuffle(all_spaces)
	for id in all_spaces:
		var dir := _direction(id, crown_id)
		if dir == "" or not _can_walk_on_from(id):
			continue
		for conn in _conns(id).duplicate():
			if _direction(id, conn) == dir:
				_unlink(id, conn)
		_link(id, crown_id)
		return


# Fallback: attach any space the Start can't reach to a random space with room.
func _connect_unvisited() -> void:
	var visited := _reachable_from(start_id)
	for id in SPACE_COUNT:
		if visited.has(id) or id == crown_id or _conns(id).size() >= MAX_CONNECTIONS:
			continue
		var possible: Array = []
		for other in SPACE_COUNT:
			if other != id and other != crown_id and _conns(other).size() < MAX_CONNECTIONS:
				possible.append(other)
		if possible.is_empty():
			continue
		var connector: int = possible[rng.randi_range(0, possible.size() - 1)]
		if _row(connector) != _row(id) and _col(connector) != _col(id) \
				and not _has_connection_in_direction(id, _direction(id, connector)) \
				and not _has_connection_in_direction(connector, _direction(connector, id)):
			_link(id, connector)
