extends SceneTree
## Native end-to-end damage and contextual loot presentation, using isolated saves.
const Main = preload("res://scenes/main.tscn")
const Saves = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Loot = preload("res://data/loot_data.gd")
const Enemy = preload("res://scripts/enemy.gd")
var game: Node
var directory: String
var checks := 0
var failures: Array[String] = []
var output := "res://test-output/combat-feedback"
var source: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var large := OS.get_cmdline_user_args().has("--large-ui")
	if large: output += "/large-ui"
	directory = "user://combat_feedback_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	game = Main.instantiate()
	game.save_manager = Saves.new(directory + "/saves")
	game._profile_store = Saves.new(directory + "/profile")
	game.settings = Settings.new(directory + "/settings")
	game.settings.set_value("master", 0.0)
	game.settings.set_value("ui_scale", 1.3 if large else 1.0)
	game.settings.save_settings()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	for frame in range(480):
		if game.world.navigation_ready: break
		await process_frame
	game.start_run("normal", false, 1)
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	game.ui.announcement_time = 0
	game.ui.announcement.hide()
	game.ui.notice_time = 0
	game._saved_time = 0
	game.exploration.set_process(false)
	game.player.position = Vector3(0, 0.1, 14)
	game.companion.position = Vector3(-1.8, 0.1, 13.5)
	source = Enemy.new()
	source.setup(game, "grunt", 1)
	game.add_child(source)
	source.set_physics_process(false)
	source.hide()
	game.player.camera.rotation = Vector3.ZERO
	for sample: Array in [[Vector3(0, 0, -2), Vector2.UP], [Vector3(0, 0, 2), Vector2.DOWN], [Vector3(2, 0, 0), Vector2.RIGHT], [Vector3(-2, 0, 0), Vector2.LEFT]]:
		_check(game._damage_direction(game.player.position + sample[0]).is_equal_approx(sample[1]), "Hit indicator follows the attacker's actual position")
	_check(game._damage_direction(Vector3.INF) == Vector2.ZERO, "Environmental damage does not invent an attacker direction")
	game.player.camera.rotation.y = PI * 0.5
	_check(game._damage_direction(game.player.position + Vector3.LEFT * 2).is_equal_approx(Vector2.UP), "Hit indicator rotates with the current camera")
	game.player.camera.rotation.y = 0
	await _show_drop("ammo", {"amount":36}, "01-ammunition")
	await _show_drop("weapon", Loot.make_weapon("anchor", 8, "legendary", 73321), "02-legendary")
	await _show_drop("attachment", Loot.roll_attachment(game.rng, 2.0, "sight"), "03-attachment")
	_clear_drops()
	game.player.camera.rotation = Vector3.ZERO
	game.exploration._scan()
	game._update_hud()
	game.ui.set_process(false)
	game.player.health = 100
	game.player.damage_cooldown = 0
	source.global_position = game.player.global_position + Vector3(1.5, 0, -2.5)
	game.player.take_damage(22, source)
	_check(is_equal_approx(game.player.health, 78), "A normal opening hit removes 22 health through the real coordinator")
	game._update_hud()
	await _capture("04-damage-direction")
	game.player.damage_cooldown = 0
	game.player.take_damage(1000000, source)
	_check(is_equal_approx(game.player.health, 38), "An extreme normal hit is capped at 40 percent of max health")
	game.player.health = 24
	game._update_hud()
	await _capture("05-low-health")
	game.running = false
	paused = false
	await game.audio.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	for folder: String in ["saves", "profile", "settings"]:
		var path := ProjectSettings.globalize_path(directory + "/" + folder)
		if DirAccess.dir_exists_absolute(path):
			for file: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(file))
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	print("COMBAT FEEDBACK: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _show_drop(kind: String, payload: Dictionary, label: String) -> void:
	_clear_drops()
	var drop: Node3D = game.exploration.drop_item(kind, payload, Vector3(0, 0.1, 11.7), true)
	game.player.camera.look_at(drop.global_position + Vector3.UP * 0.45)
	game.exploration._scan()
	game._update_hud()
	_check(game.exploration.target.get("node") == drop, "Crosshair finds the physical " + kind + " drop")
	_check(game.ui.loot_display.visible, "Crosshair shows the contextual " + kind + " card")
	await _capture(label)

func _clear_drops() -> void:
	for drop: Node in game.exploration.drops:
		if is_instance_valid(drop):
			game.exploration.remove_child(drop)
			drop.queue_free()
	game.exploration.drops.clear()
	game.exploration.target = {}

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open("res://test-output/.gdignore", FileAccess.WRITE)
	if ignore != null: ignore.close()
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK, "Native feedback capture: " + label)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
