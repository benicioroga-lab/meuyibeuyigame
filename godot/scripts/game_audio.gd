class_name MeyuiAudio
extends Node
## Original, memory-only sound design. Cached effects share eleven fixed voices;
## three synchronized loops blend a dark score, tension percussion and ambience.

const SAMPLE_RATE: int = 22050
const EFFECT_VOICES: int = 11
const ALIASES: Dictionary = {
	"gunshot": "shot", "collect": "coin", "bark": "dog", "critical": "headshot",
	"round-complete": "round", "round-start": "round", "reload-start": "reload",
	"reload-end": "reload_insert", "reload-insert": "reload_insert",
	"reload-chamber": "reload_insert", "equip": "reload_insert", "loot": "coin",
	"boss-kill": "victory", "boss-killed": "victory", "powerup": "purchase",
	"boss_kill": "victory", "boss_killed": "victory",
	"loot_uncommon": "loot_common", "loot_epic": "loot_rare", "loot_unique": "loot_mythic",
	"hover": "ui_hover", "click": "ui_click", "region_unlock": "discovery",
}
const COOLDOWNS: Dictionary = {
	"hit": 0.025, "headshot": 0.06, "kill": 0.06, "coin": 0.08,
	"dog": 0.22, "hurt": 0.12, "shield": 0.12, "empty": 0.12, "round": 0.3, "victory": 0.5,
	"ui_hover": 0.07, "ui_click": 0.055, "loot_common": 0.08, "event": 0.5, "boss": 0.8,
}
const INTERFACE_CUES: Array[String] = ["ui_hover", "ui_click", "save", "purchase", "attachment"]
const MUSIC_SECONDS: float = 12.8

var active: bool = false
var volume: float = 0.65
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _voice_cursor: int = 0
var _last_cue: Dictionary = {}
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _pressure: float = 0.0
var _duck: float = 0.0
var _prepared: bool = false
var _boss: bool = false
var _event_id: String = ""
var _category_volume: Dictionary = {"music": 0.75, "effects": 1.0, "weapons": 0.85, "ambient": 0.7, "interface": 0.8}


func _ready() -> void:
	_random.seed = 871239
	_render_library()
	for index in range(EFFECT_VOICES):
		var player := AudioStreamPlayer.new()
		player.name = "Effect%02d" % index
		player.max_polyphony = 1
		add_child(player)
		_voices.append(player)
	_music = AudioStreamPlayer.new()
	_music.name = "OriginalAmbientLoop"
	_music.max_polyphony = 1
	_music.stream = _render_music()
	add_child(_music)
	_tension = AudioStreamPlayer.new()
	_tension.name = "OriginalTensionLoop"
	_tension.max_polyphony = 1
	_tension.stream = _render_tension()
	add_child(_tension)
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "OriginalWindAndDrone"
	_ambient.max_polyphony = 1
	_ambient.stream = _render_ambient()
	add_child(_ambient)
	_prepared = true
	_apply_volume()
	set_active(active)


func set_active(enabled: bool) -> void:
	active = enabled
	if not _prepared:
		return
	for loop: AudioStreamPlayer in [_music, _tension, _ambient]:
		loop.stream_paused = not enabled
		if enabled and not loop.playing:
			loop.play()
	if not enabled:
		for player in _voices:
			player.stop()
		_last_cue.clear()


func _exit_tree() -> void:
	# Release playback ownership before AudioServer shuts down on native exit.
	_release_playback()


func shutdown() -> void:
	# stop() schedules a short backend fade; give AudioServer time to retire its
	# playback references while the scene tree is still processing before quit().
	active = false
	_release_playback()
	if is_inside_tree():
		# A SceneTreeTimer can consume the preceding slow render/test frame's delta
		# immediately. The native audio thread needs real elapsed time instead.
		var latency := AudioServer.get_output_latency()
		var drain_ms := maxi(150, ceili(latency * 2000.0 + 40.0))
		var deadline := Time.get_ticks_msec() + drain_ms
		while Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		# Playback retirement is finalized by AudioServer's next main-thread update.
		await get_tree().process_frame
		await get_tree().process_frame


func _release_playback() -> void:
	for player: AudioStreamPlayer in _voices:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for loop: AudioStreamPlayer in [_music, _tension, _ambient]:
		if is_instance_valid(loop):
			loop.stop()
			loop.stream = null
	_streams.clear()
	_prepared = false


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	if _prepared:
		_apply_volume()


func apply_settings(data: Dictionary) -> void:
	# Accept the full settings object or its audio section; omitted sliders persist.
	var settings: Dictionary = data.get("audio", data) if data.get("audio", data) is Dictionary else data
	var engine_settings: bool = settings.has("effects_audio") or settings.has("preset")
	if engine_settings:
		# GameSettings applies the master slider on AudioServer's Master bus.
		# Applying it again to each voice would square its attenuation.
		volume = 1.0
	elif settings.has("master") or settings.has("master_volume"):
		var master := float(settings.get("master", settings.get("master_volume", volume)))
		volume = clampf(master, 0.0, 1.0) if is_finite(master) else 0.0
	for category: String in _category_volume:
		var key: String = "effects_audio" if category == "effects" and engine_settings else category
		var value := float(settings.get(key, settings.get(category + "_volume", _category_volume[category])))
		_category_volume[category] = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	if _prepared:
		_apply_volume()


func set_context(boss_active: bool = false, event_id: String = "") -> void:
	_boss = boss_active
	_event_id = event_id
	if _prepared:
		_apply_music_volume()


func tick(delta: float, pressure: float = 0.0) -> void:
	if not _prepared or not active or not is_finite(delta) or not is_finite(pressure):
		return
	var elapsed := clampf(delta, 0.0, 0.25)
	_pressure = lerpf(_pressure, clampf(pressure, 0.0, 1.0), 1.0 - exp(-elapsed * 2.0))
	_duck = maxf(0.0, _duck - elapsed)
	_apply_music_volume()


func play(cue: String, weapon_id: String = "biscuit") -> void:
	if not _prepared or volume <= 0.0:
		return
	var key: String = cue.to_lower()
	key = str(ALIASES.get(key, key))
	if not active and not key in INTERFACE_CUES:
		return
	if key == "shot":
		key = _shot_key(weapon_id)
	if not _streams.has(key):
		return
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var cooldown: float = float(COOLDOWNS.get(key, 0.0))
	if cooldown > 0.0 and now - float(_last_cue.get(key, -1000.0)) < cooldown:
		return
	_last_cue[key] = now
	# Prefer a free voice. At saturation, replace one old transient without allocating.
	var voice: AudioStreamPlayer = _voices[_voice_cursor]
	for offset in range(EFFECT_VOICES):
		var index: int = (_voice_cursor + offset) % EFFECT_VOICES
		if not _voices[index].playing:
			voice = _voices[index]
			_voice_cursor = index
			break
	_voice_cursor = (_voice_cursor + 1) % EFFECT_VOICES
	voice.stop()
	voice.stream = _streams[key] as AudioStreamWAV
	var category := _cue_category(key)
	voice.set_meta("audio_category", category)
	voice.volume_db = _effect_gain(category)
	voice.pitch_scale = _random.randf_range(0.96, 1.04) if key.begins_with("shot_") or key == "dog" else 1.0
	voice.play()
	if key in ["round", "victory", "hurt", "shield", "boss", "event", "loot_mythic", "loot_legendary"]:
		_duck = maxf(_duck, 0.28 if key == "hurt" else 0.12 if key == "shield" else 0.7)
		_apply_music_volume()


func _shot_key(weapon_id: String) -> String:
	match weapon_id.to_lower():
		"hammer", "cascade", "horizon", "zero", "heavy", "shotgun", "sniper", "doorman", "lookout", "comet":
			return "shot_heavy"
		"boardwalk", "popcorn", "firefly", "ember", "voltage", "rifle", "smg", "sparrow", "anchor", "scrap", "arc":
			return "shot_rifle"
	return "shot_pistol"


func _apply_volume() -> void:
	for player in _voices:
		player.volume_db = _effect_gain(str(player.get_meta("audio_category", "effects")))
	_apply_music_volume()


func _cue_category(key: String) -> String:
	if key.begins_with("shot_") or key in ["reload", "reload_insert", "empty"]:
		return "weapons"
	if key in INTERFACE_CUES:
		return "interface"
	return "effects"


func _effect_gain(category: String) -> float:
	var gain := volume * float(_category_volume.get(category, 1.0)) * 0.55
	return linear_to_db(gain) if gain > 0.00001 else -80.0


func _apply_music_volume() -> void:
	var duck_gain: float = 0.52 if _duck > 0.0 else 1.0
	var music_gain := volume * float(_category_volume["music"]) * duck_gain
	_music.volume_db = linear_to_db(maxf(0.0001, music_gain * 0.20))
	var tension := maxf(_pressure, 0.88 if _boss else 0.24 if not _event_id.is_empty() else 0.0)
	_tension.volume_db = linear_to_db(maxf(0.0001, music_gain * tension * 0.24))
	var ambient_gain := volume * float(_category_volume["ambient"]) * (0.25 if _event_id == "storm" else 0.14)
	_ambient.volume_db = linear_to_db(maxf(0.0001, ambient_gain))
	if music_gain <= 0.00001:
		_music.volume_db = -80.0
		_tension.volume_db = -80.0
	if ambient_gain <= 0.00001:
		_ambient.volume_db = -80.0


func _buffer(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(ceili(seconds * SAMPLE_RATE))
	return samples


func _tone(samples: PackedFloat32Array, start: float, duration: float, hz: float, end_hz: float, level: float, warmth: float = 0.0) -> void:
	var begin: int = int(start * SAMPLE_RATE)
	var count: int = mini(int(duration * SAMPLE_RATE), samples.size() - begin)
	for index in range(maxi(0, count)):
		var t: float = float(index) / SAMPLE_RATE
		var fraction: float = t / duration
		var envelope: float = minf(t / 0.003, 1.0) * exp(-fraction * 5.5) * minf((duration - t) / 0.008, 1.0)
		var phase: float = TAU * (hz * t + (end_hz - hz) * t * t / (2.0 * duration))
		samples[begin + index] += (sin(phase) + warmth * sin(phase * 2.0)) * envelope * level


func _noise(samples: PackedFloat32Array, start: float, duration: float, level: float, cutoff: float = 3000.0) -> void:
	var begin: int = int(start * SAMPLE_RATE)
	var count: int = mini(int(duration * SAMPLE_RATE), samples.size() - begin)
	var smooth: float = 0.0
	var alpha: float = 1.0 - exp(-TAU * cutoff / SAMPLE_RATE)
	for index in range(maxi(0, count)):
		var t: float = float(index) / SAMPLE_RATE
		smooth += (_random.randf_range(-1.0, 1.0) - smooth) * alpha
		var envelope: float = minf(t / 0.0015, 1.0) * exp(-t / duration * 6.0) * minf((duration - t) / 0.006, 1.0)
		samples[begin + index] += smooth * envelope * level


func _notes(samples: PackedFloat32Array, notes: Array, spacing: float, duration: float, level: float) -> void:
	for index in range(notes.size()):
		var hz: float = 440.0 * pow(2.0, (float(notes[index]) - 69.0) / 12.0)
		_tone(samples, index * spacing, duration, hz, hz, level, 0.17)


func _pcm(samples: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in range(samples.size()):
		# Reserve headroom and smoothly limit overlapping layers inside each sample.
		var value: float = samples[index] / (1.0 + absf(samples[index]) * 0.4)
		bytes.encode_s16(index * 2, int(clampf(value, -0.85, 0.85) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


func _render_library() -> void:
	for family in ["pistol", "rifle", "heavy"]:
		var heavy: bool = family == "heavy"
		var rifle: bool = family == "rifle"
		var samples: PackedFloat32Array = _buffer(0.38 if heavy else 0.21)
		_noise(samples, 0.0, 0.19 if heavy else 0.06, 0.62 if heavy else 0.48, 3600.0 if rifle else 2600.0)
		_tone(samples, 0.0, 0.3 if heavy else 0.13, 115.0 if heavy else 240.0 if rifle else 185.0, 40.0 if heavy else 72.0, 0.50 if heavy else 0.34, 0.15)
		_noise(samples, 0.022, 0.04, 0.18, 1300.0)
		if heavy:
			_noise(samples, 0.028, 0.30, 0.30, 650.0)
		_streams["shot_" + family] = _pcm(samples)
	for key in ["hit", "headshot", "kill"]:
		var samples: PackedFloat32Array = _buffer(0.27)
		_noise(samples, 0.0, 0.035, 0.19, 2200.0)
		var hz: float = 1320.0 if key == "headshot" else 740.0 if key == "kill" else 930.0
		_tone(samples, 0.0, 0.09, hz, hz * 0.88, 0.17)
		if key == "headshot":
			_tone(samples, 0.0, 0.13, 1980.0, 1760.0, 0.06)
			_tone(samples, 0.0, 0.10, 100.0, 60.0, 0.21)
		if key == "kill":
			_tone(samples, 0.055, 0.19, 1110.0, 1060.0, 0.13)
		_streams[key] = _pcm(samples)
	for key in ["reload", "reload_insert", "empty"]:
		var samples: PackedFloat32Array = _buffer(0.4)
		_noise(samples, 0.0, 0.045, 0.23, 3200.0)
		_tone(samples, 0.0, 0.055, 340.0, 115.0, 0.15, 0.2)
		if key == "reload":
			_noise(samples, 0.13, 0.16, 0.13, 1900.0)
		if key == "reload_insert":
			_noise(samples, 0.08, 0.06, 0.20, 1600.0)
			_tone(samples, 0.075, 0.08, 150.0, 75.0, 0.15)
		_streams[key] = _pcm(samples)
	var coin: PackedFloat32Array = _buffer(0.30)
	_notes(coin, [81, 88], 0.045, 0.20, 0.17)
	_streams["coin"] = _pcm(coin)
	var purchase: PackedFloat32Array = _buffer(0.65)
	_notes(purchase, [69, 72, 76, 81], 0.075, 0.36, 0.20)
	_streams["purchase"] = _pcm(purchase)
	var dog: PackedFloat32Array = _buffer(0.40)
	for delay in [0.0, 0.16]:
		_tone(dog, delay, 0.15, 230.0, 85.0, 0.31, 0.55)
		_noise(dog, delay, 0.12, 0.26, 740.0)
	_streams["dog"] = _pcm(dog)
	var hurt: PackedFloat32Array = _buffer(0.30)
	# A close cloth slap and chest thud arrive together; the short exhale leaves
	# the impact readable through gunfire without a long explosive bass tail.
	_noise(hurt, 0.0, 0.048, 0.26, 1850.0)
	_tone(hurt, 0.0, 0.16, 178.0, 74.0, 0.43, 0.22)
	_tone(hurt, 0.009, 0.18, 87.0, 54.0, 0.17)
	_noise(hurt, 0.038, 0.19, 0.20, 720.0)
	_streams["hurt"] = _pcm(hurt)
	# Absorption is a restrained resonant ping, separate from bodily damage.
	var shield: PackedFloat32Array = _buffer(0.26)
	_tone(shield, 0.0, 0.21, 740.0, 592.0, 0.23)
	_tone(shield, 0.0, 0.17, 1109.0, 961.0, 0.13)
	_tone(shield, 0.004, 0.10, 1640.0, 1510.0, 0.045)
	_tone(shield, 0.0, 0.08, 126.0, 84.0, 0.12)
	_noise(shield, 0.0, 0.025, 0.085, 2200.0)
	_streams["shield"] = _pcm(shield)
	var round_sound: PackedFloat32Array = _buffer(1.10)
	_notes(round_sound, [57, 60, 64, 69], 0.12, 0.64, 0.23)
	_tone(round_sound, 0.0, 0.24, 110.0, 48.0, 0.27)
	_streams["round"] = _pcm(round_sound)
	var victory: PackedFloat32Array = _buffer(1.75)
	_notes(victory, [57, 64, 69, 72, 76, 81], 0.16, 0.78, 0.24)
	_tone(victory, 0.0, 0.38, 120.0, 45.0, 0.3)
	_streams["victory"] = _pcm(victory)
	var step: PackedFloat32Array = _buffer(0.09)
	_noise(step, 0.0, 0.07, 0.085, 850.0)
	_tone(step, 0.0, 0.06, 86.0, 45.0, 0.06)
	_streams["step"] = _pcm(step)
	_render_progression_cues()


func _render_music() -> AudioStreamWAV:
	var samples: PackedFloat32Array = _buffer(MUSIC_SECONDS)
	# Four spacious minor/suspended chords: slow bowed harmonics, felt plucks and
	# distant bass. The parallel drum stem supplies intensity without speeding music.
	var roots: Array = [38, 34, 41, 36]
	var upper: Array = [57, 53, 60, 55]
	for bar in range(4):
		var hz := _midi_hz(int(roots[bar]))
		_pad(samples, bar * 3.2, 3.18, hz, 0.16)
		_pad(samples, bar * 3.2, 3.18, hz * 1.4983, 0.045)
		_pad(samples, bar * 3.2 + 0.18, 2.98, _midi_hz(int(upper[bar])), 0.04)
		for beat in range(4):
			var start := bar * 3.2 + beat * 0.8
			_tone(samples, start, 0.62, hz * 0.5, hz * 0.5, 0.10, 0.1)
			if beat == 1 or beat == 3:
				var note := _midi_hz(int(upper[bar]) + (7 if beat == 3 else 0))
				_tone(samples, start + 0.12, 0.85, note, note * 0.999, 0.075, 0.08)
				_tone(samples, start + 0.39, 0.72, note * 2.0, note * 2.0, 0.018)
	return _pcm(samples, true)


func _render_tension() -> AudioStreamWAV:
	var samples: PackedFloat32Array = _buffer(MUSIC_SECONDS)
	for beat in range(32):
		var start := beat * 0.4
		_tone(samples, start, 0.20, 95.0, 38.0, 0.36 if beat % 4 == 0 else 0.12)
		_noise(samples, start + 0.20, 0.055, 0.08 if beat % 2 == 0 else 0.045, 3500.0)
		if beat % 4 == 2:
			_noise(samples, start, 0.19, 0.18, 1250.0)
			_tone(samples, start, 0.14, 176.0, 126.0, 0.12, 0.45)
		if beat % 8 == 7:
			_tone(samples, start + 0.21, 0.12, 230.0, 95.0, 0.08)
	return _pcm(samples, true)


func _render_ambient() -> AudioStreamWAV:
	var samples: PackedFloat32Array = _buffer(MUSIC_SECONDS)
	var smooth := 0.0
	for index in range(samples.size()):
		var t := float(index) / SAMPLE_RATE
		var wind := 0.65 + 0.35 * sin(TAU * t / MUSIC_SECONDS * 3.0)
		smooth += (_random.randf_range(-1.0, 1.0) - smooth) * 0.028
		var fade := minf(1.0, minf(t, MUSIC_SECONDS - t) / 0.08)
		# Frequencies are exact loop harmonics, so the low drone has no seam.
		samples[index] = (smooth * wind * 0.26 + sin(TAU * 42.5 * t) * 0.035 + sin(TAU * 63.75 * t) * 0.014) * fade
	return _pcm(samples, true)


func _pad(samples: PackedFloat32Array, start: float, duration: float, hz: float, level: float) -> void:
	var begin := int(start * SAMPLE_RATE)
	var count := mini(int(duration * SAMPLE_RATE), samples.size() - begin)
	for index in range(maxi(0, count)):
		var t := float(index) / SAMPLE_RATE
		var envelope := sin(PI * t / duration)
		var phase := TAU * hz * t
		var body := sin(phase) * 0.65 + sin(phase * 1.003) * 0.24 + sin(phase * 2.0) * 0.08
		samples[begin + index] += body * envelope * envelope * level


func _midi_hz(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)


func _render_progression_cues() -> void:
	var patterns := {
		"loot_common": [74, 81], "loot_rare": [69, 76, 83],
		"loot_legendary": [57, 64, 69, 76, 81], "loot_mythic": [50, 57, 62, 69, 74, 81],
		"attachment": [67, 74, 79], "save": [60, 67, 72],
		"discovery": [50, 57, 60, 64, 69], "event": [38, 45, 50, 53],
		"boss": [26, 33, 38, 39], "ui_hover": [79], "ui_click": [72, 79],
	}
	for key: String in patterns:
		var interface_cue := key in ["ui_hover", "ui_click"]
		var spacing := 0.025 if interface_cue else 0.10
		var duration := 0.06 if interface_cue else 0.64 if key in ["boss", "loot_mythic", "discovery"] else 0.36
		var seconds := maxf(0.12, (patterns[key].size() - 1) * spacing + duration + 0.02)
		var samples := _buffer(seconds)
		_notes(samples, patterns[key], spacing, duration, 0.08 if interface_cue else 0.20)
		if key in ["boss", "event", "discovery", "loot_mythic", "loot_legendary"]:
			_tone(samples, 0.0, minf(seconds, 0.7), 84.0, 31.0, 0.28, 0.22)
			_noise(samples, 0.0, minf(seconds, 0.5), 0.15, 500.0)
		if key == "boss":
			_pad(samples, 0.0, seconds - 0.02, 43.65, 0.19)
			_pad(samples, 0.0, seconds - 0.02, 46.25, 0.12)
		_streams[key] = _pcm(samples)
