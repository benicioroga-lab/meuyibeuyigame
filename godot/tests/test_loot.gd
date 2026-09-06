extends SceneTree

const Loot = preload("res://data/loot_data.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Data = preload("res://data/game_data.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_starter_and_live_state()
	_test_generation_and_quality()
	_test_all_models_and_modifiers()
	_test_attachments_and_ammo_conservation()
	_test_inventory_transactions()
	_test_forge_rerolls_and_previews()
	_test_save_round_trip_and_rejection()
	if failures.is_empty():
		print("PASS: %d looter inventory checks" % checks)
		quit(0)
	else:
		printerr("FAIL: %d / %d looter checks" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, context: String) -> void:
	checks += 1
	if not condition:
		failures.append(context)
		push_error(context)

func _test_starter_and_live_state() -> void:
	var inventory: Inventory = Inventory.new()
	inventory.create_starter()
	var item: Dictionary = inventory.equipped()
	var stats: Dictionary = inventory.stats()
	_check(item.model_id == "biscuit", "Starter is the reliable pistol")
	_check(is_equal_approx(float(stats.damage), float(Data.WEAPONS.biscuit.damage)), "Starter preserves exact base damage")
	_check(int(item.magazine) == 12 and int(item.reserve) == 84, "Starter uses finite base ammo")
	item.magazine = 3
	_check(int(inventory.find_item(String(item.uid)).magazine) == 3, "Equipped is a live instance for combat ammo")
	item.upgrade_level = 35
	_check(float(inventory.stats().damage) > float(stats.damage), "Weapon upgrades continue beyond a fixed five-tier cap")
	var damage_35: float = float(inventory.stats().damage)
	item.upgrade_level = 36
	_check(float(inventory.stats().damage) > damage_35, "Later upgrades remain meaningful")
	_check(not inventory.equip("missing") and inventory.equipped_id == item.uid, "Invalid equipment never unsets the valid weapon")
	var empty: Inventory = Inventory.new()
	_check(empty.stats().is_empty() and not empty.auto_equip(), "An empty inventory safely reports no weapon")

func _test_generation_and_quality() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20319
	var low_rank_sum: int = 0
	var high_rank_sum: int = 0
	var independent_rolls: Dictionary = {}
	var inventory: Inventory = Inventory.new()
	for index: int in range(1200):
		low_rank_sum += Loot.rarity_rank(Loot.roll_rarity(rng, 1.0))
		high_rank_sum += Loot.rarity_rank(Loot.roll_rarity(rng, 3.0))
		var weapon: Dictionary = Loot.roll_weapon(1 if index < 40 else 20, rng, 1.4)
		_check(not weapon.is_empty(), "Roll %d produces an item" % index)
		var parsed: Variant = JSON.parse_string(JSON.stringify(weapon))
		_check(parsed is Dictionary and inventory._valid_weapon(parsed), "Roll %d survives JSON and schema validation" % index)
		_check(not independent_rolls.has(String(weapon.uid)), "Roll %d has a unique instance ID" % index)
		independent_rolls[String(weapon.uid)] = true
		if index < 40:
			_check(String(weapon.model_id) == "biscuit", "Round-one ordinary drops respect weapon unlocks")
		var stats: Dictionary = inventory.stats(weapon)
		_check(float(stats.damage) > 0.0 and int(stats.magazine_size) > 0 and float(stats.reload_time) > 0.0, "Roll %d has usable stats" % index)
	_check(high_rank_sum > low_rank_sum * 1.5, "Higher risk quality materially increases expected rarity")
	var seeded_a: Dictionary = Loot.make_weapon("boardwalk", 12, "legendary", 71341)
	var seeded_b: Dictionary = Loot.make_weapon("boardwalk", 12, "legendary", 71341)
	_check(JSON.stringify(seeded_a) == JSON.stringify(seeded_b), "Seeded weapon generation is deterministic")
	_check(seeded_a.modifiers.size() >= 3 and Loot.LEGENDARY_NAMES.has(String(seeded_a.modifiers[0])), "Legendary rolls guarantee a signature behavior")
	var rerolled: Dictionary = Loot.make_weapon("boardwalk", 12, "legendary", 91341)
	_check(JSON.stringify(seeded_a.rolls) != JSON.stringify(rerolled.rolls), "Two identical weapon models can roll different attributes")
	var high: Dictionary = Loot.roll_weapon(100000, rng, 2.0, "mythic")
	_check(String(high.rarity) == "mythic" and is_finite(float(inventory.stats(high).damage)), "Very high rounds remain rollable without overflow")

func _test_all_models_and_modifiers() -> void:
	var inventory: Inventory = Inventory.new()
	var families: Dictionary = {}
	for model_id: String in Data.WEAPONS:
		var item: Dictionary = Loot.make_weapon(model_id, 5, "rare", 1901)
		var stats: Dictionary = inventory.stats(item)
		families[String(stats.family)] = true
		_check(stats.model_id == model_id and stats.id == model_id, "Legacy ID and instance model agree for %s" % model_id)
		_check(float(stats.sustained_dps) < float(stats.dps), "Reload downtime is included in sustainable DPS for %s" % model_id)
	_check(families.size() == 10, "Ten distinct weapon archetypes exist")
	for modifier: String in Loot.MODIFIERS:
		var item: Dictionary = Loot.starter_weapon()
		item.modifiers = [modifier]
		_check(inventory.stats(item).modifiers.has(modifier), "Combat receives behavior %s" % modifier)
	var shotgun: Dictionary = inventory.stats(Loot.make_weapon("doorman", 1, "common", 52))
	_check(int(shotgun.pellets) == 7 and float(shotgun.spread) > 0.02, "Shotgun has a real pellet pattern")
	var sniper: Dictionary = inventory.stats(Loot.make_weapon("lookout", 1, "common", 54))
	_check(int(sniper.penetration) >= 1 and float(sniper.zoom) >= 2.0, "Sniper includes range, penetration and zoom")

func _attachment(id: String, uid: String, rarity: String = "common") -> Dictionary:
	return {"uid":uid, "id":id, "slot":String(Loot.ATTACHMENTS[id].slot), "rarity":rarity, "roll":1.0}

func _test_attachments_and_ammo_conservation() -> void:
	var inventory: Inventory = Inventory.new()
	inventory.create_starter()
	var uid: String = inventory.equipped_id
	var item: Dictionary = inventory.equipped()
	var original: Dictionary = inventory.stats()
	_check(inventory.add_attachment(_attachment("extended_mag", "extended-1")), "Attachment can enter the backpack")
	_check(inventory.install(uid, "extended-1"), "Every starter weapon supports an extended magazine")
	_check(inventory.attachments.is_empty() and item.attachments.has("magazine"), "Installed attachment moves rather than duplicating")
	_check(int(inventory.stats().magazine_size) > int(original.magazine_size), "Attachment changes actual magazine capacity")
	_check(int(item.magazine) == 12, "Larger magazine does not create ammunition")
	item.magazine = 15
	item.reserve = 5
	_check(inventory.add_attachment(_attachment("quick_mag", "quick-1")), "Replacement attachment enters inventory")
	_check(inventory.install(uid, "quick-1"), "Installing into an occupied slot swaps the attachment")
	_check(inventory.attachments.size() == 1 and inventory.attachments[0].uid == "extended-1", "Swapped attachment returns to the backpack")
	_check(int(item.magazine) + int(item.reserve) == 20, "Shrinking a magazine transfers spare rounds to reserve")
	_check(float(inventory.stats().reload_time) < float(original.reload_time), "Quick magazine changes actual reload time")
	_check(not inventory.add_attachment(_attachment("quick_mag", "quick-1")), "An installed attachment cannot be duplicated")
	_check(inventory.uninstall(uid, "magazine"), "Installed attachment can be removed")
	_check(int(item.magazine) + int(item.reserve) == 20, "Removing a part preserves finite ammunition")
	var effect_parts: Array[String] = ["ember_barrel", "frost_mag", "echo_receiver", "perforator"]
	for id: String in effect_parts:
		_check(inventory.add_attachment(_attachment(id, "part-" + id, "epic")), "%s enters inventory" % id)
		_check(inventory.install(uid, "part-" + id), "%s fits any weapon" % id)
		_check(inventory.stats().modifiers.has(String(Loot.ATTACHMENTS[id].modifier)), "%s changes the combat behavior" % id)
	var plain_grip: Dictionary = _attachment("grip", "grip-plain")
	var rare_grip: Dictionary = _attachment("grip", "grip-rare", "mythic")
	inventory.add_attachment(plain_grip)
	inventory.install(uid, "grip-plain")
	var plain_recoil: float = float(inventory.stats().recoil)
	inventory.add_attachment(rare_grip)
	inventory.install(uid, "grip-rare")
	_check(float(inventory.stats().recoil) < plain_recoil, "Attachment rarity changes real performance")
	item.reserve = 180
	_check(inventory.uninstall(uid, "underbarrel") and int(item.reserve) == 180, "Attachment changes preserve reserve earned through run perks")
	var restored: Inventory = Inventory.new()
	_check(restored.import_state(JSON.parse_string(JSON.stringify(inventory.export_state()))) and int(restored.equipped().reserve) == 180, "Run-perk reserve survives inventory loading until player applies its final capacity")

func _test_inventory_transactions() -> void:
	var inventory: Inventory = Inventory.new()
	inventory.create_starter()
	inventory.capacity = 3
	var starter_uid: String = inventory.equipped_id
	var first: Dictionary = Loot.make_weapon("boardwalk", 6, "epic", 615)
	var second: Dictionary = Loot.make_weapon("hammer", 3, "rare", 971)
	_check(inventory.add_item(first) and inventory.add_item(second), "Distinct instances fit the backpack")
	_check(not inventory.add_item(Loot.make_weapon("anchor", 3, "rare", 411)), "Capacity rejection never silently deletes a weapon")
	_check(not inventory.add_item(first), "Duplicate weapon IDs are rejected")
	_check(inventory.remove(starter_uid, "sell").is_empty(), "Equipped weapon is protected from selling")
	_check(inventory.set_flag(String(first.uid), "favorite", true), "A weapon can be favorited")
	_check(inventory.remove(String(first.uid), "dismantle").is_empty(), "Favorites are protected from dismantling")
	_check(inventory.materials == 0, "Rejected dismantle grants no materials")
	_check(inventory.set_flag(String(first.uid), "junk", true) and not inventory.find_item(String(first.uid)).favorite, "Favorite and junk are mutually exclusive")
	_check(inventory.auto_equip() and inventory.equipped_id != first.uid, "Auto-equip skips items explicitly marked as junk")
	inventory.equip(starter_uid)
	var removed: Dictionary = inventory.remove(String(first.uid), "dismantle")
	_check(not removed.is_empty() and inventory.materials == 8, "Epic dismantle grants exactly its material value")
	_check(inventory.remove(String(first.uid), "dismantle").is_empty() and inventory.materials == 8, "A dismantled instance cannot pay twice")
	_check(inventory.sorted_items("rarity")[0].rarity == "rare", "Rarity sorting presents quality first")
	_check(inventory.sorted_items("recent")[0].uid == second.uid, "Recent sorting tracks acquisition order")
	_check(not inventory.set_flag(starter_uid, "damage", true), "Flag API cannot alter weapon statistics")

func _test_forge_rerolls_and_previews() -> void:
	var inventory: Inventory = Inventory.new()
	inventory.create_starter()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 71904
	var uid: String = inventory.equipped_id
	var preview: Dictionary = inventory.upgrade_preview(uid)
	_check(float(preview.to.damage) > float(preview.from.damage), "Forge preview shows the real next damage")
	_check(int(preview.cost) == Data.upgrade_cost(0) and int(inventory.equipped().upgrade_level) == 0, "A preview costs no coins and mutates no upgrade state")
	_check(inventory.upgrade_preview("missing").is_empty(), "Invalid upgrade preview has no purchasable result")
	_check(inventory.reroll_cost(uid, "modifier") == inventory.reroll_cost(uid, "modifiers"), "Modifier aliases share one price")
	_check(inventory.reroll_cost("missing", "stat") == 0 and inventory.reroll_cost(uid, "unknown") == 0, "Invalid rerolls quote no charge")
	var unchanged: String = JSON.stringify(inventory.export_state())
	_check(not inventory.reroll(uid, "unknown", rng) and not inventory.reroll("missing", "stat", rng), "Invalid rerolls are rejected")
	_check(JSON.stringify(inventory.export_state()) == unchanged, "Rejected rerolls cannot consume ammo or increment costs")
	for kind: String in ["stat", "element", "modifier", "modifiers", "attachment", "manufacturer"]:
		var before: Dictionary = inventory.equipped().duplicate(true)
		var cost: int = inventory.reroll_cost(uid, kind)
		var count: int = int(before.get("reroll_count", 0))
		_check(inventory.reroll(uid, kind, rng), "Forge rerolls %s" % kind)
		var after: Dictionary = inventory.equipped()
		_check(int(after.reroll_count) == count + 1 and inventory.reroll_cost(uid, kind) > cost, "A successful %s reroll raises the next price once" % kind)
		_check(int(after.magazine) + int(after.reserve) <= int(before.magazine) + int(before.reserve), "%s reroll cannot manufacture ammunition" % kind)
		if kind == "element":
			_check(String(after.element) != String(before.element), "Element reroll selects a different elemental identity")
		elif kind == "manufacturer":
			_check(String(after.manufacturer) != String(before.manufacturer), "Manufacturer reroll selects a different manufacturer")
		elif kind in ["modifier", "modifiers"]:
			_check(JSON.stringify(after.modifiers) != JSON.stringify(before.modifiers), "Modifier reroll changes a behavior")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(inventory.export_state()))
	var restored: Inventory = Inventory.new()
	_check(restored.import_state(saved) and int(restored.equipped().reroll_count) == 6, "Escalating reroll investment survives JSON save/load")
	_check(restored.reroll_cost(uid, "stat") == inventory.reroll_cost(uid, "stat"), "Save/load cannot reset reroll prices")
	inventory.add_attachment(_attachment("ember_barrel", "reroll-ember"))
	inventory.install(uid, "reroll-ember")
	_check(inventory.reroll(uid, "element", rng), "Element reroll works with an elemental attachment installed")
	_check(String(inventory.stats().element) == String(inventory.equipped().element), "Elemental attachments cannot hide the purchased primary element")
	_check(inventory.stats().modifiers.has("burn"), "An attachment retains its own elemental behavior in a mixed build")
	var legendary: Dictionary = Loot.make_weapon("boardwalk", 12, "legendary", 7044)
	_check(inventory.add_item(legendary), "Legendary enters the forge test")
	for index: int in range(25):
		_check(inventory.reroll(String(legendary.uid), "modifier", rng), "Legendary behavior reroll %d succeeds" % index)
		_check(Loot.LEGENDARY_NAMES.has(String(inventory.find_item(String(legendary.uid)).modifiers[0])), "Legendary reroll %d preserves a signature behavior" % index)

func _test_save_round_trip_and_rejection() -> void:
	var source: Inventory = Inventory.new()
	source.create_starter()
	var item: Dictionary = Loot.make_weapon("arc", 31, "legendary", 3381)
	_check(source.add_item(item), "Save fixture enters inventory")
	source.equip(String(item.uid))
	source.equipped().magazine = 2
	source.equipped().reserve = 13
	source.equipped().upgrade_level = 19
	source.set_flag(String(item.uid), "favorite", true)
	source.materials = 81
	source.add_attachment(_attachment("scope", "saved-scope", "rare"))
	var encoded: String = JSON.stringify(source.export_state())
	var parsed: Dictionary = JSON.parse_string(encoded)
	var restored: Inventory = Inventory.new()
	_check(restored.import_state(parsed), "JSON save imports with numeric types restored")
	_check(restored.equipped_id == source.equipped_id and restored.items.size() == 2 and restored.materials == 81, "Equipment, backpack and crafting currency survive")
	_check(int(restored.equipped().magazine) == 2 and int(restored.equipped().reserve) == 13, "Save cannot refill ammunition")
	_check(int(restored.equipped().upgrade_level) == 19 and restored.equipped().favorite, "Upgrade investment and favorite protection survive")
	_check(is_equal_approx(float(restored.stats().damage), float(source.stats().damage)), "Weapon performance survives save and restore")
	var stable: String = JSON.stringify(restored.export_state())
	var bad: Dictionary = parsed.duplicate(true)
	bad.equipped_id = "missing"
	_check(not restored.import_state(bad), "A missing equipped reference is rejected")
	_check(JSON.stringify(restored.export_state()) == stable, "Failed import preserves every prior value")
	bad = parsed.duplicate(true)
	bad.items[1].rolls.damage = -10
	_check(not restored.import_state(bad), "Malformed negative roll is rejected")
	bad = parsed.duplicate(true)
	bad.items[1].modifiers = ["arbitrary_script"]
	_check(not restored.import_state(bad), "Unknown behavior ID is rejected")
	bad = parsed.duplicate(true)
	bad.items.append(bad.items[1].duplicate(true))
	_check(not restored.import_state(bad), "Duplicate saved weapon IDs cannot duplicate equipment")
	bad = parsed.duplicate(true)
	bad.attachments.append(bad.items[1].attachments.values()[0].duplicate(true))
	_check(not restored.import_state(bad), "A saved part cannot be both equipped and in the backpack")
	_check(JSON.stringify(restored.export_state()) == stable, "All corrupt-state failures remain atomic")
	for invalid: Variant in [{}, [], 15, null]:
		bad = parsed.duplicate(true)
		bad.items[1].manufacturer = invalid
		_check(not restored.import_state(bad), "Malformed manufacturer type rejects cleanly")
		bad = parsed.duplicate(true)
		bad.attachments[0].slot = invalid
		_check(not restored.import_state(bad), "Malformed attachment slot type rejects cleanly")
		bad = parsed.duplicate(true)
		bad.equipped_id = invalid
		_check(not restored.import_state(bad), "Malformed equipped reference type rejects cleanly")
