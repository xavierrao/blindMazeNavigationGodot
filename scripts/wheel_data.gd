class_name WheelData
extends RefCounted
## Every wheel's contents live in this one file, so revamping them means editing
## the lists in good(), bad() and shadow() - no other code needs to change.
##
## A wheel is a list of equal-size slices. To change the odds, change how many
## slices of each kind a wheel has (the number after each slice below).
##
## Slice format: {"label": String, "effect": String, "amount": int, "color": Color}
## Effects the game understands: "gold", "nothing", "to_shadow", "return_home", "stay".
## Keep labels short (they are written on the wheel).
##
## These are PLACEHOLDER contents until you design the real wheels.

const SHADOW_TOTAL_SLICES := 8
const SHADOW_BASE_ESCAPE := 1   # "Home" slices on the first spin
const SHADOW_MAX_ESCAPE := 6    # one more is added after each failed spin, up to this


static func title(wheel_name: String) -> String:
	match wheel_name:
		"good": return "Good Wheel"
		"bad": return "Bad Wheel"
		"shadow": return "Shadow Wheel"
	return "Wheel"


static func get_wheel(wheel_name: String, shadow_spins: int = 0) -> Array:
	match wheel_name:
		"good": return good()
		"bad": return bad()
		"shadow": return shadow(shadow_spins)
	return []


# ---------------------------------------------------------------------------
# The wheels (edit these!)
# ---------------------------------------------------------------------------

static func good() -> Array:
	return _build([
		[gold(1), 3],
		[gold(2), 2],
		[gold(3), 1],
		[nothing(), 1],
	])


static func bad() -> Array:
	return _build([
		[gold(-1), 3],
		[gold(-2), 2],
		[nothing(), 1],
		[to_shadow(), 1],
	])


# spins_so_far = how many times this player has already spun during this stay.
static func shadow(spins_so_far: int) -> Array:
	var escape := mini(SHADOW_BASE_ESCAPE + spins_so_far, SHADOW_MAX_ESCAPE)
	return _build([
		[return_home(), escape],
		[stay(), SHADOW_TOTAL_SLICES - escape],
	])


# ---------------------------------------------------------------------------
# Slice builders
# ---------------------------------------------------------------------------

static func gold(amount: int) -> Dictionary:
	return {
		"label": "%+d gold" % amount,
		"effect": "gold",
		"amount": amount,
		"color": Color("#2E8B57") if amount > 0 else Color("#C0392B"),
	}


static func nothing() -> Dictionary:
	return {"label": "Nothing", "effect": "nothing", "color": Color("#7F8790")}


static func to_shadow() -> Dictionary:
	return {"label": "Shadow", "effect": "to_shadow", "color": Color("#222222")}


static func return_home() -> Dictionary:
	return {"label": "Home", "effect": "return_home", "color": Color("#2F6FDE")}


static func stay() -> Dictionary:
	return {"label": "Stuck", "effect": "stay", "color": Color("#4A4A4A")}


# Turns [[slice, count], ...] into one list, spread out so equal slices
# are not next to each other where possible.
static func _build(groups: Array) -> Array:
	var remaining: Array = []
	var total := 0
	for group in groups:
		remaining.append(group[1])
		total += group[1]

	var result: Array = []
	var last := -1
	for _n in total:
		var best := -1
		for i in groups.size():
			if remaining[i] <= 0 or i == last:
				continue
			if best == -1 or remaining[i] > remaining[best]:
				best = i
		if best == -1:
			best = last  # only the previous kind is left
		remaining[best] -= 1
		result.append(groups[best][0])
		last = best
	return result
