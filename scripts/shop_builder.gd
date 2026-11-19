class_name ShopBuilder
extends RefCounted
## Decides what every shop sells at the start of a game, from the shop random
## stream, so the same seed always gives the same shops.
##
## The recipe (from the rules doc), for 3 shops of 4 items:
##   - Items with pool "every_shop" (Scout Lens) go in EVERY shop.
##   - Items with pool "guaranteed" (Distraction Bell, Prospector's Pick) each go in
##     ONE shop, each in a different shop where possible.
##   - The remaining slots are filled with random items: 1 Economy, 2 Information,
##     2 Interference and 2 Movement, never two items that are "never_with" each other.
##   - Every item sits in only one shop (except the every-shop ones).

const SLOTS_PER_SHOP := 4

## How many random items to draw from each category.
const RANDOM_QUOTAS := {"Economy": 1, "Information": 2, "Interference": 2, "Movement": 2}

## While some items aren't built yet, only stock items that work. Any quota or
## guaranteed item that can't be filled is replaced by other working items, so
## every shop still has 4. Turn this off once every item is implemented.
static var only_implemented := true


## Returns {"shops": {shop_space_id: {"items": [ids], "stock": {id: n}, "restock": {id: rounds}}},
##          "announced": [item ids for sale somewhere]}.
static func build(shop_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var contents := {}
	for shop_id in shop_ids:
		contents[shop_id] = []

	# 1. Staples
	var every_shop: Array = []
	var guaranteed: Array = []
	for item in ItemData.ITEMS:
		if only_implemented and not item["implemented"]:
			continue
		if item["pool"] == "every_shop":
			every_shop.append(item["id"])
		elif item["pool"] == "guaranteed":
			guaranteed.append(item["id"])
	for item_id in every_shop:
		for shop_id in shop_ids:
			contents[shop_id].append(item_id)
	var shuffled_shops := shop_ids.duplicate()
	_shuffle(shuffled_shops, rng)
	for i in guaranteed.size():
		contents[shuffled_shops[i % shuffled_shops.size()]].append(guaranteed[i])

	# 2. Random items: fill the quotas first, then top up with anything else usable
	var free_slots := 0
	for shop_id in shop_ids:
		free_slots += maxi(0, SLOTS_PER_SHOP - contents[shop_id].size())

	var chosen: Array = []
	for category in RANDOM_QUOTAS:
		var candidates := _random_candidates(category, chosen)
		_shuffle(candidates, rng)
		for item_id in candidates:
			if chosen.size() >= free_slots or _count_in_category(chosen, category) >= int(RANDOM_QUOTAS[category]):
				break
			if _conflicts(item_id, chosen):
				continue
			chosen.append(item_id)
	var topup := _random_candidates("", chosen)
	_shuffle(topup, rng)
	for item_id in topup:
		if chosen.size() >= free_slots:
			break
		if not _conflicts(item_id, chosen):
			chosen.append(item_id)

	# 3. Spread them over the free slots at random
	var slots: Array = []
	for shop_id in shop_ids:
		for _i in maxi(0, SLOTS_PER_SHOP - contents[shop_id].size()):
			slots.append(shop_id)
	_shuffle(slots, rng)
	for i in mini(chosen.size(), slots.size()):
		contents[slots[i]].append(chosen[i])

	# 4. Tidy up: stable order inside each shop, starting stock, announcement
	var shops := {}
	var announced := {}
	for shop_id in shop_ids:
		var ids: Array = contents[shop_id]
		ids.sort_custom(func(a: String, b: String) -> bool: return _item_index(a) < _item_index(b))
		var stock := {}
		for item_id in ids:
			stock[item_id] = ItemData.start_stock(item_id)
			announced[item_id] = true
		shops[shop_id] = {"items": ids, "stock": stock, "restock": {}}
	var announced_ids: Array = announced.keys()
	announced_ids.sort_custom(func(a: String, b: String) -> bool: return _item_index(a) < _item_index(b))
	return {"shops": shops, "announced": announced_ids}


# Random-pool items in `category` ("" = any category) that are usable and not already chosen.
static func _random_candidates(category: String, chosen: Array) -> Array:
	var result: Array = []
	for item in ItemData.ITEMS:
		if item["pool"] != "random" or chosen.has(item["id"]):
			continue
		if only_implemented and not item["implemented"]:
			continue
		if category != "" and item["category"] != category:
			continue
		result.append(item["id"])
	return result


static func _count_in_category(item_ids: Array, category: String) -> int:
	var count := 0
	for item_id in item_ids:
		if ItemData.find(item_id)["category"] == category:
			count += 1
	return count


# True if this item can't share a game with something already chosen.
static func _conflicts(item_id: String, chosen: Array) -> bool:
	var never_with: Array = ItemData.find(item_id)["never_with"]
	for other in chosen:
		if never_with.has(other) or ItemData.find(other)["never_with"].has(item_id):
			return true
	return false


static func _item_index(item_id: String) -> int:
	for i in ItemData.ITEMS.size():
		if ItemData.ITEMS[i]["id"] == item_id:
			return i
	return 9999


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
