extends SceneTree
## Run with --headless --path godot --script res://tests/test_director.gd.
## Exercises the real director and PCM audio with deterministic actor feedback.

const Director = preload("res://scripts/run_director.gd")
const Audio = preload("res://scripts/game_audio.gd")

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		printerr("FAIL: Director/audio test timed out")
		quit(1)
	)
	_test_start_and_population()
	_test_capacity_and_summons()
	_test_endless_rounds()
	_test_events_and_recovery()
	_test_serialization()
	await _test_audio()
	print("DIRECTOR_AUDIO checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("FAIL: " + message)


func _state(director: RefCounted) -> Dictionary:
	return {"health_ratio": 0.9, "ammo_ratio": 0.8, "alive": director.spawned - director.killed,
		"kills_per_second": 0.5, "seconds_without_damage": 4.0, "region_id": "largo"}


func _test_start_and_population() -> void:
	var director := Director.new()
	director.start("normal", 0, 345)
	_check(director.round_number == 1 and director.wave_total == 6, "Normal starts with a moderate six-enemy wave")
	_check(director.phase == "prepare" and is_equal_approx(director.phase_time, 3.0), "New runs receive three seconds to prepare")
	_check(director.tick(2.0, _state(director)).is_empty(), "Preparation never spawns enemies early")
	var actions: Array[Dictionary] = director.tick(1.0, _state(director))
	_check(actions.size() == 1 and actions[0]["type"] == "round_start", "Preparation emits exactly one round-start action")
	_check(director.spawned == 0 and director.phase == "combat", "Round-start transition does not secretly reserve an enemy")
	var spawned := director.tick(0.2, _state(director))
	_check(spawned.size() == 1 and spawned[0]["type"] == "spawn" and director.spawned == 1, "A spawn action immediately reserves exactly one slot")
	director.register_kill(false)
	_check(director.killed == 0, "Non-wave deaths never advance wave completion")
	director.register_kill()
	director.register_kill()
	_check(director.killed == 1, "Kill count cannot exceed reserved spawn slots")
	var before := director.export_state()
	_check(director.tick(-1.0, {}).is_empty() and director.tick(NAN, {}).is_empty(), "Invalid elapsed time emits no actions")
	_check(director.export_state() == before, "Invalid elapsed time cannot mutate a run")
	director.start("unknown", -8, 99)
	_check(director.difficulty_id == "normal" and director.chaos_level == 0, "Invalid starting options use bounded defaults")
	director.start("nightmare", 10, 99)
	_check(director.wave_total > 6 and director.get_modifiers()["enemy_speed"] <= 1.2, "Difficulty increases population while chaos speed stays bounded")


func _test_capacity_and_summons() -> void:
	var director := Director.new()
	director.start("normal", 0, 812)
	director.round_number = 100
	director.wave_total = 200
	director.phase = "combat"
	for step in range(80):
		director.tick(2.0, _state(director))
	_check(director.spawned == 24, "An unhandled horde stops at twenty-four simultaneous actors")
	_check(not director.add_summon(), "Summoners cannot bypass the alive cap")
	director.register_kill()
	_check(director.add_summon(), "A summon can reserve an available actor slot")
	_check(director.wave_total == 201 and director.spawned == 25, "A summon participates in both population and completion accounting")
	for index in range(3):
		director.register_kill()
		_check(director.add_summon(), "The next allowed summon reserves a slot")
	director.register_kill()
	_check(not director.add_summon(), "Summons are capped at four per round")
	_check(director.wave_total == 204, "Rejected summons do not inflate wave size")
	var pending := director.spawned
	director.tick(5.0, {"alive": 24})
	_check(director.spawned == pending, "A caller's live actor count also prevents overcrowding")
	director.phase = "rest"
	_check(not director.add_summon(), "Rest periods reject late summon callbacks")


func _test_endless_rounds() -> void:
	var director := Director.new()
	director.start("normal", 2, 392111)
	var starts: Dictionary = {}
	var bosses: Dictionary = {}
	var completed: int = 0
	var event_count: int = 0
	var last_population: int = 0
	for step in range(12000):
		var actions := director.tick(1.0, _state(director))
		for action: Dictionary in actions:
			match str(action["type"]):
				"spawn":
					if str(action["kind"]).begins_with("boss"):
						bosses[director.round_number] = str(action["kind"])
					director.register_kill()
				"round_start":
					_check(not starts.has(action["round"]), "Each round emits its start only once")
					starts[action["round"]] = true
					_check(int(action["total"]) >= last_population, "Endless wave populations never shrink between rounds")
					last_population = int(action["total"])
				"round_complete":
					completed += 1
					_check(director.spawned == director.wave_total and director.killed == director.wave_total, "Round completion waits for every scheduled enemy")
					_check(int(action["reward"]) > 0, "Completed rounds provide a usable reward")
				"event_start":
					event_count += 1
		if completed >= 35:
			break
	_check(completed == 35, "The real director completes thirty-five consecutive rounds")
	for number in [5, 10, 15, 20, 25, 30, 35]:
		_check(bosses.has(number), "Every fifth round includes a real boss spawn: %d" % number)
	_check(bosses.get(5) == "boss" and bosses.get(10) == "boss_bulwark" and bosses.get(15) == "boss_conductor", "Bosses rotate across distinct actor kinds")
	_check(event_count >= 6, "Long expeditions schedule repeated dynamic events")
	director.round_number = 999
	director.force_rest(0.0)
	var next := director.tick(0.1, _state(director))
	_check(director.round_number == 1000 and director.phase == "combat" and next[0]["type"] == "round_start", "There is no hard final round")
	_check(director.wave_total > 1000, "Long-run population continues to grow beyond the old eighty-enemy cap")


func _test_events_and_recovery() -> void:
	for id: String in Director.EVENTS:
		var director := Director.new()
		director.start("normal", 0, 176)
		director.phase = "combat"
		director.wave_total = 200
		var actions := director.force_event(id)
		_check(actions.size() == 1 and actions[0]["type"] == "event_start", "A real event-start action exposes %s" % id)
		_check(director.force_event("storm").is_empty(), "An event cannot silently replace a running event")
		var mods: Dictionary = director.get_modifiers()
		match id:
			"blackout": _check(mods["visibility"] < 0.5 and mods["ambient"] < 0.5, "Blackout exposes actual lighting modifiers")
			"storm": _check(mods["visibility"] < 1.0 and mods["enemy_speed"] < 1.0, "Storm alters visibility and movement")
			"elite_invasion":
				var elite_spawn := director.tick(0.2, _state(director))
				_check(elite_spawn[0]["type"] == "spawn" and elite_spawn[0]["elite"], "Elite invasion reserves actual elite actors")
			"double_loot": _check(is_equal_approx(mods["loot"], 2.0), "Double loot doubles the real loot multiplier")
			"supply": _check(mods["supply"], "Supply event exposes the supply placement effect")
			"boss_hunt":
				var boss_spawn := director.tick(0.2, _state(director))
				_check(boss_spawn[0]["type"] == "spawn" and str(boss_spawn[0]["kind"]).begins_with("boss"), "Boss hunt schedules an actual boss")
		var finishes := 0
		for step in range(12):
			for action: Dictionary in director.tick(5.0, {"alive": 24}):
				if action["type"] == "event_complete":
					finishes += 1
		_check(finishes == 1 and director.active_event.is_empty(), "%s expires and rewards exactly once" % id)
		_check(is_equal_approx(float(director.get_modifiers()["loot"]), 1.0), "Expired event modifiers reset for %s" % id)
	var recovery := Director.new()
	recovery.start("normal", 0, 123)
	recovery.phase = "combat"
	var low := {"health_ratio": 0.2, "ammo_ratio": 0.03, "alive": 0}
	var recovery_actions := recovery.tick(0.1, low)
	_check(recovery.metrics["relief"] and recovery.metrics["spawn_interval"] > 1.3, "Scarce health and ammunition slow incoming pressure")
	_check(recovery_actions[0]["type"] == "event_start" and recovery_actions[0]["event"]["id"] == "supply", "Low resources trigger a real recovery supply action")
	var duplicate_supplies := 0
	for step in range(10):
		for action: Dictionary in recovery.tick(5.0, low):
			if action["type"] == "event_start":
				duplicate_supplies += 1
	_check(duplicate_supplies == 0, "Recovery supplies obey their ninety-second cooldown")


func _test_serialization() -> void:
	var original := Director.new()
	original.start("hard", 3, 748213)
	original.tick(3.0, _state(original))
	original.tick(1.1, _state(original))
	original.force_event("boss_hunt")
	var encoded := JSON.stringify(original.export_state())
	var restored := Director.new()
	var data: Dictionary = JSON.parse_string(encoded)
	_check(restored.import_state(data), "Director accepts its JSON-round-tripped state")
	_check(JSON.stringify(restored.export_state()) == encoded, "Counters, timers, pending boss and RNG survive serialization exactly")
	for step in range(120):
		var original_actions := original.tick(0.4, _state(original))
		var restored_actions := restored.tick(0.4, _state(restored))
		_check(original_actions == restored_actions, "Loaded run produces the same future actions at tick %d" % step)
		for action: Dictionary in original_actions:
			if action["type"] == "spawn":
				original.register_kill()
				restored.register_kill()
	var before := restored.export_state()
	for invalid: Dictionary in [{}, {"version": 3}, {"phase": "lost"}, {"killed": 999999}, {"wave_total": {}}, {"elapsed": "broken"}, {"rng_state": "bad"}, {"active_event": {"id": "unknown"}}, {"active_event": {"id": "storm", "remaining": "bad"}}]:
		var bad := before.duplicate(true)
		bad.merge(invalid, true)
		if invalid.is_empty():
			bad.clear()
		_check(not restored.import_state(bad), "Malformed save is rejected: %s" % invalid)
		_check(restored.export_state() == before, "Rejected save leaves the running director intact")


func _test_audio() -> void:
	var audio := Audio.new()
	root.add_child(audio)
	await process_frame
	_check(audio._prepared and audio._voices.size() == Audio.EFFECT_VOICES, "Audio initializes one bounded pool of effect voices")
	_check(audio._streams.size() == 28, "The original library contains twenty-eight cached cues")
	var required := ["loot_common", "loot_rare", "loot_legendary", "loot_mythic", "attachment", "save", "ui_hover", "ui_click", "discovery", "event", "boss", "hurt", "shield"]
	var signatures: Dictionary = {}
	for key: String in required:
		_check(audio._streams.has(key), "The cue %s is playable" % key)
		var stream: AudioStreamWAV = audio._streams[key]
		_check(stream.data.size() > 1000 and stream.mix_rate == Audio.SAMPLE_RATE, "%s has a rendered native PCM stream" % key)
		var digest := stream.data.hex_encode().sha256_text()
		_check(not signatures.has(digest), "%s has distinct sound content" % key)
		signatures[digest] = true
		var audible := false
		var peak := 0
		for offset in range(0, stream.data.size(), 14):
			var sample := absi(stream.data.decode_s16(offset))
			peak = maxi(peak, sample)
			audible = audible or sample > 100
		_check(audible and peak < 29000, "%s is audible with PCM headroom" % key)
	for loop: AudioStreamPlayer in [audio._music, audio._tension, audio._ambient]:
		var stream: AudioStreamWAV = loop.stream
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and is_equal_approx(stream.get_length(), Audio.MUSIC_SECONDS), "Music layers loop on the same phrase duration")
	audio.set_active(true)
	var playback_refs: Array[WeakRef] = []
	for loop: AudioStreamPlayer in [audio._music, audio._tension, audio._ambient]:
		playback_refs.append(weakref(loop.get_stream_playback()))
	var boss_cue: AudioStreamWAV = audio._streams["victory"]
	audio.play("boss_kill")
	var boss_voice: AudioStreamPlayer = audio._voices[(audio._voice_cursor - 1 + Audio.EFFECT_VOICES) % Audio.EFFECT_VOICES]
	_check(boss_voice.stream == boss_cue, "The coordinator's boss_kill cue plays the victory sound")
	playback_refs.append(weakref(boss_voice.get_stream_playback()))
	boss_cue = null
	audio.apply_settings({"master": 0.8, "music": 0.6, "effects": 0.5, "weapons": 0.3, "ambient": 0.4, "interface": 0.9})
	for cue: String in ["hurt", "shield"]:
		audio.play(cue)
		var impact_voice: AudioStreamPlayer = audio._voices[(audio._voice_cursor - 1 + Audio.EFFECT_VOICES) % Audio.EFFECT_VOICES]
		_check(impact_voice.stream == audio._streams[cue], "%s uses its pre-rendered impact stream" % cue)
		_check(impact_voice.get_meta("audio_category") == "effects", "%s follows the sound-effects slider" % cue)
		playback_refs.append(weakref(impact_voice.get_stream_playback()))
		var impact_cursor: int = audio._voice_cursor
		audio.play(cue)
		_check(audio._voice_cursor == impact_cursor, "%s cooldown prevents duplicate audio from simultaneous hits" % cue)
		var impact: AudioStreamWAV = audio._streams[cue]
		var immediate_energy := 0.0
		for offset in range(0, int(Audio.SAMPLE_RATE * 0.03) * 2, 2):
			var value := float(impact.data.decode_s16(offset)) / 32767.0
			immediate_energy += value * value
		_check(sqrt(immediate_energy / (Audio.SAMPLE_RATE * 0.03)) > 0.07, "%s has an immediate audible attack within thirty milliseconds" % cue)
	audio.tick(0.2, 0.0)
	var quiet: float = audio._tension.volume_db
	audio.set_context(true, "storm")
	_check(audio._tension.volume_db > quiet, "Boss context raises a separate percussion layer")
	var count: int = audio.get_child_count()
	for index in range(80):
		audio.play("shot", "sparrow")
		var played: AudioStreamPlayer = audio._voices[(audio._voice_cursor - 1 + Audio.EFFECT_VOICES) % Audio.EFFECT_VOICES]
		playback_refs.append(weakref(played.get_stream_playback()))
	_check(audio.get_child_count() == count and audio._streams.size() == 28, "Dense combat allocates neither extra voices nor new sound caches")
	audio.apply_settings({"weapons": 0.0})
	for voice: AudioStreamPlayer in audio._voices:
		if voice.get_meta("audio_category", "") == "weapons":
			_check(voice.volume_db <= -80.0, "Weapon volume independently silences active gunshots")
	_check(audio._music.volume_db > -80.0, "Muting weapons preserves the music channel")
	audio.apply_settings({"preset":"low", "master":0.4, "effects":0.0, "effects_audio":0.7})
	_check(is_equal_approx(audio._category_volume["effects"], 0.7), "Visual effect density does not mute sound effects")
	_check(is_equal_approx(audio.volume, 1.0), "Native master bus applies master gain only once")
	audio.apply_settings({"preset":"high", "effects":1.0, "effects_audio":0.0})
	_check(is_zero_approx(audio._category_volume["effects"]), "Sound effect slider mutes independently from visual quality")
	audio.set_active(false)
	_check(audio._music.stream_paused and audio._tension.stream_paused and audio._ambient.stream_paused, "Pausing freezes all synchronized music layers")
	for cycle in range(3):
		audio.set_active(true)
		audio.set_active(false)
	_check(audio._music.get_stream_playback() == playback_refs[0].get_ref(), "Rapid pause and resume reuse the same music playback")
	audio.play("ui_click")
	var ui_voice: AudioStreamPlayer = audio._voices[(audio._voice_cursor - 1 + Audio.EFFECT_VOICES) % Audio.EFFECT_VOICES]
	playback_refs.append(weakref(ui_voice.get_stream_playback()))
	var ui_played := false
	for voice: AudioStreamPlayer in audio._voices:
		ui_played = ui_played or voice.get_meta("audio_category", "") == "interface"
	_check(ui_played, "Menu interface cues remain available while combat audio is paused")
	audio.set_volume(0.0)
	_check(audio._music.volume_db <= -80.0 and audio._ambient.volume_db <= -80.0, "Master mute silences both music and ambience")
	var shutdown_started := Time.get_ticks_msec()
	await audio.shutdown()
	_check(Time.get_ticks_msec() - shutdown_started >= 150, "Shutdown allows the native mixer real elapsed time even after a slow frame")
	var retained_playbacks := 0
	for reference: WeakRef in playback_refs:
		if reference.get_ref() != null:
			retained_playbacks += 1
	_check(retained_playbacks == 0, "All %d native playbacks retire after rapid fire, pause and shutdown (retained=%d)" % [playback_refs.size(), retained_playbacks])
	_check(not audio._prepared and audio._streams.is_empty(), "Orderly shutdown releases cached resources before quitting")
	audio.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(audio), "Audio playback ownership releases on scene teardown")
