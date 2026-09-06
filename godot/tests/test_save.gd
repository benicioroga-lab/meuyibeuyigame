extends SceneTree
## Isolated real-disk tests. Never touches user save slots or configuration.
const Saves = preload("res://scripts/save_manager.gd")
var _directory: String
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_directory = "user://test_saves_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var saves = Saves.new(_directory)
	_check(saves.list_slots().size() == 3 and not saves.has_save(), "Three empty slots, no continuation")
	_check(not saves.save_slot(0, {"round": 1}).ok and not saves.save_slot(4, {"round": 1}).ok, "Reject slots outside 1..3")
	var state: Dictionary = {
		"round_number": 19, "coins": 4567, "seconds": 672.25,
		"player": {"health": 76.5, "position": [-3.0, 6.5, -40.0], "magazine": 11, "reserve": 64,
			"inventory": [{"id": "roll-a", "model": "biscuit", "rarity": "legendary", "damage": 45.3,
				"attachments": {"barrel": {"id": "shock", "tier": 3}}, "modifiers": ["chain", "last_round"], "favorite": true}]},
		"dog": {"type": "collector", "level": 7, "skills": ["ammo", "revive"]},
		"perks": {"reload": 5}, "world": {"opened": ["canal", "vault"], "claimed_chests": ["chest-19"]},
		"stats": {"kills": 130, "bosses": ["bellkeeper"]}, "event": {"type": "blackout", "remaining": 31.5},
	}
	var metadata: Dictionary = {"round": 19, "region": "Cais Esquecido", "time": 672.25, "dog_level": 7, "weapon_name": "Eco Final"}
	_check(saves.save_slot(1, state, metadata).ok, "Save complete nested run with rolls, parts, companion and world state")
	var loaded: Dictionary = saves.load_slot(1)
	_check(loaded.ok and not loaded.recovered and loaded.state.player.inventory[0].attachments.barrel.id == "shock", "Nested attachments survive JSON round trip")
	_check(loaded.state.world.claimed_chests == state.world.claimed_chests and loaded.state.event.remaining == 31.5, "Opened loot and event timer survive")
	_check(loaded.state.player.position == state.player.position and loaded.metadata.region == metadata.region, "Position, metadata and time survive")
	_check(saves.latest_slot() == 1 and saves.has_save(), "Continue resolves latest valid slot")
	state.coins = 9999
	_check(saves.save_slot(1, state, metadata).ok, "Atomic overwrite succeeds while preserving previous save")
	_check(FileAccess.file_exists(saves.storage_root.path_join("slot_1.json.bak")), "Previous valid primary becomes backup")
	_check(not FileAccess.file_exists(saves.storage_root.path_join("slot_1.json.tmp")), "Successful transaction leaves no temporary file")
	_write(saves.storage_root.path_join("slot_1.json"), "{broken:interrupt")
	loaded = saves.load_slot(1)
	_check(loaded.ok and loaded.recovered and loaded.state.coins == 4567, "Corrupted primary recovers previous valid backup")
	_check(saves.save_slot(1, state, metadata).ok, "Save resumes after backup recovery")
	_write(saves.storage_root.path_join("slot_1.json"), "damaged again")
	_check(saves.load_slot(1).state.coins == 4567, "Corrupt primary never overwrites healthy backup")
	var bad: Dictionary = state.duplicate(true)
	bad.coins = -1
	_check(not saves.save_slot(2, bad).ok, "Reject negative economy")
	bad.coins = NAN
	_check(not saves.save_slot(2, bad).ok, "Reject NaN")
	bad.coins = 1
	bad.player.position = Vector3.ONE
	_check(not saves.save_slot(2, bad).ok, "Reject native Variant values instead of executable serialization")
	bad = {"round": 1, "nested": {}}
	var nested: Dictionary = bad.nested
	for depth in range(45):
		nested["next"] = {}
		nested = nested.next
	_check(not saves.save_slot(2, bad).ok, "Reject excessively nested saves")
	_check(not saves.save_slot(2, {"round": 1.5}).ok, "Reject fractional rounds")
	var identifier_state: Dictionary = {"round":1, "powerups":{}}
	identifier_state.powerups.frenzy = 12.0
	_check(saves.save_slot(3, identifier_state).ok and saves.load_slot(3).state.powerups.frenzy == 12.0, "Native StringName dictionary identifiers serialize as safe JSON strings")
	saves.delete_slot(3)
	var migration: Dictionary = {"version": 1, "slot": 2, "state": state, "metadata": metadata, "saved_unix": 1}
	_write(saves.storage_root.path_join("slot_2.json"), JSON.stringify(migration))
	loaded = saves.load_slot(2)
	_check(loaded.ok and loaded.migrated and loaded.version == 2, "Version 1 JSON migrates without mutating disk")
	_check(saves.save_slot(2, loaded.state, loaded.metadata).ok and not saves.load_slot(2).migrated, "Next save writes migrated schema")
	var valid_file: String = FileAccess.get_file_as_string(saves.storage_root.path_join("slot_2.json"))
	var tampered: Dictionary = JSON.parse_string(valid_file)
	tampered.body = tampered.body.replace('"coins":9999', '"coins":9998')
	_write(saves.storage_root.path_join("slot_3.json"), JSON.stringify(tampered))
	_check(not saves.load_slot(3).ok, "Checksum and slot identity reject tampered/copied envelope")
	_write(saves.storage_root.path_join("slot_2.json"), JSON.stringify({"version": 999, "state": state}))
	loaded = saves.load_slot(2)
	_check(not loaded.ok and loaded.get("unsupported_version", false), "Newer save version is rejected even with valid older backup")
	_check(not saves.save_slot(2, state).ok, "Saving cannot silently downgrade a future-version slot")
	_check(saves.list_slots()[1].exists and not saves.list_slots()[1].valid, "Unsupported occupied slot is not presented as empty")
	_check(saves.delete_slot(2) and not saves.list_slots()[1].exists, "Explicit deletion removes primary and sidecars only for chosen slot")
	_check(saves.list_slots()[0].exists, "Deleting another slot preserves first slot")
	_check(saves.save_slot(3, state, metadata).ok, "Third slot writes independently")
	DirAccess.rename_absolute(saves.storage_root.path_join("slot_3.json"), saves.storage_root.path_join("slot_3.json.tmp"))
	loaded = saves.load_slot(3)
	_check(loaded.ok and loaded.recovered and loaded.recovery_source == "temporary", "Interrupted initial save recovers verified temporary file")
	var blocker: String = saves.storage_root.path_join("not_a_directory")
	_write(blocker, "fixture")
	var blocked = Saves.new(blocker)
	_check(not blocked.save_slot(1, state).ok, "Unwritable target reports failure without destroying source saves")
	for slot in range(1, 4):
		saves.delete_slot(slot)
	DirAccess.remove_absolute(blocker)
	DirAccess.remove_absolute(saves.storage_root)
	print("SAVE TESTS: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
