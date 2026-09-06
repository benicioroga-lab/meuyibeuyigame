extends SceneTree
## Native menus are measured at the smallest supported window and largest UI scale.
## The fixture isolates saves/settings so confirmation tests never touch user slots.
const Main = preload("res://scenes/main.tscn")
const Saves = preload("res://scripts/save_manager.gd")
const Settings = preload("res://scripts/game_settings.gd")
var game: Node
var directory: String
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	directory = "user://ui_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	root.size = Vector2i(1280, 720)
	game = Main.instantiate()
	game.save_manager = Saves.new(directory + "/saves")
	game._profile_store = Saves.new(directory + "/profile")
	game.settings = Settings.new(directory + "/settings")
	game.settings.set_value("master", 0.0)
	game.settings.set_value("ui_scale", 1.3)
	game.settings.set_value("resolution", [1280, 720])
	game.settings.save_settings()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	await _settle()
	_check(game.ui.continue_button.disabled, "Continue is disabled when all slots are empty")
	_measure(game.ui.menu, "main menu")
	game.ui.show_new_game()
	await _settle()
	_measure(game.ui.detail, "new expedition")
	_check(game.ui.selected_slot == 1, "New expedition selects the first empty slot")
	game.ui.difficulty.item_selected.emit(3)
	game.ui.chaos.button_pressed = true
	_check(game.ui.new_difficulty == "insane" and game.ui.new_chaos, "Difficulty and Chaos update from actual controls")
	for category: String in ["graphics", "gameplay", "audio", "accessibility"]:
		game.ui._show_settings_category(category)
		await _settle()
		_measure(game.ui.detail, "settings " + category)
	_check(is_equal_approx(game.ui.ui_scale, 1.3), "Settings apply the requested UI scale")
	game.ui.show_load_game()
	await _settle()
	_measure(game.ui.detail, "empty save slots")
	for child: Node in game.ui.detail_body.get_children():
		if child is Button: _check(child.disabled, "Empty save slots cannot load")
	for frame in range(480):
		if game.world.navigation_ready: break
		await process_frame
	game.start_run("normal", false, 1)
	game.player.set_physics_process(false)
	game.companion.set_physics_process(false)
	_check(game.save_game(1), "Fixture stores a real valid expedition in its isolated slot")
	game.return_to_menu()
	game.ui.show_new_game()
	game.ui.selected_slot = 1
	game.ui._start()
	await _settle()
	_check(game.ui.detail_mode == "confirm" and not game.running, "Occupied slot requires confirmation before starting")
	_measure(game.ui.detail, "replace confirmation")
	game.ui.cancel_confirmation.call()
	_check(game.ui.detail_mode == "new" and not game.running, "Cancel preserves the existing expedition")
	_check(game.save_manager.load_slot(1).ok, "Cancel leaves the saved snapshot valid")
	game.ui.show_load_game()
	await _settle()
	_measure(game.ui.detail, "populated save slots")
	game.ui.show_extras()
	await _settle()
	_measure(game.ui.detail, "archive")
	game.ui.update_hud({"round":100,"coins":123456,"health":73,"max_health":145,"magazine":24,"reserve":168,"weapon_name":"Biscoiteira Experimental","district":"Passarela do Reservatório","dog_level":12,"dog_status":"buscando suprimentos","objective":"Abra a rota do Reservatório e enfrente o Porteiro.","boss_name":"O Porteiro","boss_health":700,"boss_max_health":1000})
	game.ui.show_pause()
	await _settle()
	_measure(game.ui.pause_menu, "pause summary")
	game.ui.hide_menus()
	var current_stats: Dictionary = game.player.get_weapon_stats()
	var found_stats := current_stats.duplicate(true)
	found_stats["damage"] = float(current_stats.damage) * 1.3
	game.ui._update_loot({"item":{"rarity":"legendary"}, "stats":found_stats,"current":current_stats})
	game.ui._update_powerups({"infinite_ammo":24,"double_damage":12,"frenzy":18,"magnet":5,"overcharge":14})
	await _settle()
	_measure(game.ui.hud, "combat HUD")
	_check(game.ui.powerup_labels.size() == 3, "Multiple buffs keep a compact bounded HUD")
	_check(game.ui.loot_rows[0].arrow.text == "↑", "Loot comparison shows the improved damage immediately")
	_check(game.ui.loot_rows.size() == 5, "Loot compares damage, cadence, magazine, reload and precision")
	_check(game.ui.loot_display.get_global_rect().end.y < 530, "Loot leaves the ammunition HUD visible")
	game.ui._update_loot({"type":"ammo", "item":{"name":"Munição","amount":24}, "stats":{"amount":24,"reserve":48,"max_reserve":168,"collectable":24}, "current":current_stats})
	await _settle()
	_measure(game.ui.loot_display, "ammunition loot")
	_check(game.ui.loot_thumbnail.kind == "ammo" and game.ui.labels.loot_details.text.contains("24 CARTUCHOS"), "Ammunition has a cartridge thumbnail and actual quantity")
	_check(not game.ui.loot_stats_box.visible and game.ui.labels.loot_prompt.text.contains("+24"), "Ammunition presents pickup capacity without irrelevant weapon statistics")
	game.ui._update_loot({"type":"ammo", "item":{"amount":24}, "stats":{"reserve":168,"max_reserve":168,"collectable":0}})
	_check(game.ui.labels.loot_prompt.text == "RESERVA CHEIA", "Full reserve gives a clear pickup explanation")
	# Reproduce the GPU path: short supply card, two-line legendary name, then
	# a one-line attachment. Text ink and separators must settle independently.
	found_stats.name = "FUZIL DO ÚLTIMO RECADO"
	found_stats.modifiers = ["shock", "critical_blast", "last_word"]
	game.ui._update_loot({"type":"weapon", "item":{"name":found_stats.name,"rarity":"legendary","level":8}, "stats":found_stats,"current":current_stats})
	await _settle()
	_check(game.ui.labels.loot_name.get_line_count() == 2, "Regression fixture renders a two-line legendary name")
	_check_loot_text("two-line legendary")
	var attachment_stats := current_stats.duplicate(true)
	attachment_stats.reload_time = float(current_stats.reload_time) * .76
	attachment_stats.precision = minf(99, float(current_stats.precision) + 1)
	game.ui._update_loot({"type":"attachment", "item":{"name":"Troca rápida","slot":"magazine","rarity":"rare","description":"Recarga mais rápida, pente menor."}, "stats":attachment_stats,"current":current_stats})
	await _settle()
	_measure(game.ui.loot_display, "attachment loot")
	_check_loot_text("attachment after legendary")
	_check(game.ui.labels.loot_name.text == "TROCA RÁPIDA" and game.ui.labels.loot_found.text == "COM PEÇA", "Attachment comparison labels the projected equipped weapon explicitly")
	_check(game.ui.loot_rows[3].arrow.text == "↑", "A shorter reload is marked as an improvement")
	game.ui._update_loot({"type":"powerup","item":{"name":"Sobrecarga","description":"Disparos elétricos temporários.","duration":24},"stats":{"duration":24}})
	await _settle()
	_measure(game.ui.loot_display, "powerup loot")
	_check(game.ui.labels.loot_level.text == "24s" and not game.ui.loot_stats_box.visible, "Powerups show duration instead of invented weapon statistics")
	game.ui._update_loot({})
	_check(not game.ui.loot_display.visible, "Leaving the item clears the contextual panel")
	_test_damage_feedback()
	game.ui._update_powerups({})
	_check(not game.ui.powerup_display.visible, "Expired powerups leave no stale HUD icons")
	game.ui.apply_settings({"ui_scale":1.3,"crosshair":false,"hitmarkers":false,"crosshair_color":"33ccff","hitmarker_color":"ffee22"})
	game.ui.show_hit(true, true)
	_check(not game.ui.reticle.enabled and game.ui.reticle.hit_time == 0, "Accessibility toggles disable crosshair and hitmarkers")
	game.ui.show_game_over(100, 123456)
	await _settle()
	_measure(game.ui.game_over, "expedition ended")
	paused = false
	game.running = false
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
	print("UI TESTS: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	for frame in range(4): await process_frame

func _check_loot_text(stage: String) -> void:
	var previous_bottom: float = -INF
	for row: Dictionary in game.ui.loot_rows:
		var line: HBoxContainer = row.before.get_parent()
		var line_rect := line.get_global_rect()
		_check(line_rect.position.y >= previous_bottom, stage + ": attribute rows do not overlap")
		for text: Label in [line.get_child(0), row.before, row.arrow, row.after]:
			var font: Font = text.get_theme_font("font")
			var font_size: int = text.get_theme_font_size("font_size")
			var ink_size := font.get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var text_rect := text.get_global_rect()
			_check(ink_size.x <= text_rect.size.x + .5 and ink_size.y <= text_rect.size.y + .5, "%s: full glyphs fit for %s (ink %s, box %s)" % [stage,text.text,ink_size,text_rect.size])
			_check(line_rect.grow(.5).encloses(text_rect), stage + ": caption and values remain within their own attribute row")
			_check(text_rect.end.y < row.meter.get_global_rect().position.y, stage + ": the stat separator does not cross text")
		previous_bottom = row.meter.get_global_rect().end.y
	_check(previous_bottom < game.ui.labels.loot_details.get_global_rect().position.y, stage + ": precision and its separator remain above item details")
	_check(game.ui.labels.loot_details.get_global_rect().end.y < game.ui.labels.loot_prompt.get_global_rect().position.y, stage + ": details remain above the pickup action")

func _test_damage_feedback() -> void:
	var veil: Control = game.ui.damage_screen
	game.ui.apply_settings({"ui_scale":1.3,"reduced_flashes":false})
	veil.clear()
	game.ui.show_damage(20, Vector2.RIGHT)
	_check(veil.amount > .4 and veil.directions.size() == 1, "A real hit immediately creates a strong vignette and a directional cue")
	_check(veil.vignette.visible and veil.vignette.material is ShaderMaterial, "Damage uses a single continuous shader overlay")
	var normal_strength: float = veil.vignette_material.get_shader_parameter("edge_strength")
	_check(veil.arc_center(0).x > 640 and is_equal_approx(veil.arc_center(0).y, 360), "An attack from the right appears on the right of the crosshair")
	game.ui.show_damage(12, Vector2.UP)
	_check(veil.arc_center(1).y < 360, "An attack from the front appears above the crosshair")
	game.ui.show_damage(3, Vector2.RIGHT)
	_check(veil.directions.size() == 2, "Repeated hits from the same direction refresh a bounded cue")
	game.ui.update_hud({"health":10,"max_health":100})
	_check(veil.directions.size() == 2, "HUD health updates preserve the direction from the damage event")
	_check(game.ui.labels.critical_health.visible, "Low health displays a readable warning")
	var first: float = veil.pulse()
	veil.tick(.4)
	_check(absf(first - veil.pulse()) > .05, "Low-health emphasis pulses slowly")
	game.ui.apply_settings({"ui_scale":1.3,"reduced_flashes":true})
	first = veil.pulse()
	veil.tick(.4)
	_check(is_equal_approx(first, veil.pulse()), "Reduced flashes replaces the pulse with steady emphasis")
	_check(float(veil.vignette_material.get_shader_parameter("edge_strength")) < normal_strength, "Reduced flashes also lowers the actual vignette opacity")
	veil.tick(2.0)
	_check(veil.amount == 0 and veil.directions.is_empty(), "Transient damage returns to a clean center after its feedback window")
	veil.clear()
	_check(not veil.vignette.visible and float(veil.vignette_material.get_shader_parameter("edge_strength")) == 0.0, "Cleared damage removes the shader overlay completely")
	game.ui.show_damage(18, Vector2.LEFT, true)
	_check(veil.amount == 0 and veil.shield_amount > 0 and veil.directions[0].absorbed, "Absorbed damage uses a shield cue without a false red health hit")
	var shield_tint: Color = veil.vignette_material.get_shader_parameter("edge_tint")
	_check(shield_tint.b > shield_tint.r, "The continuous shield border retains its distinct tint")
	game.ui.update_hud({"health":100,"max_health":100})
	_check(not game.ui.labels.critical_health.visible and veil.danger == 0, "Recovering health removes persistent warning and vignette")
	for index in range(12): game.ui.show_damage(8, Vector2.from_angle(index * .48))
	_check(veil.directions.size() <= 4, "Crossfire has a fixed upper bound on active directional indicators")
	veil.clear()
	game.ui.show_damage(10)
	_check(veil.amount > 0 and veil.directions.is_empty(), "Unknown damage sources show no invented attack direction")
	game.ui.show_menu()
	_check(veil.amount == 0 and veil.directions.is_empty(), "Returning to the menu clears damage feedback")
	game.ui.hide_menus()

func _measure(node: Node, page: String, in_scroll: bool = false) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Label and not node.text.is_empty():
		_check(node.size.y >= node.get_theme_font_size("font_size"), "%s text has readable height: %s" % [page, node.text.left(32)])
		_check(node.size.x > 2, "%s text has visible width: %s" % [page, node.text.left(32)])
	if node is Control and not in_scroll:
		var rectangle: Rect2 = node.get_global_rect()
		var bounds := Rect2(Vector2(-2, -2), Vector2(1284, 724))
		_check(bounds.encloses(rectangle), "%s fits 1280x720: %s %s" % [page, node.name, rectangle])
	elif node is Control and in_scroll:
		var rectangle: Rect2 = node.get_global_rect()
		_check(rectangle.position.x >= -2 and rectangle.end.x <= 1282, "%s scroll content fits window width: %s %s" % [page, node.name, rectangle])
	for child: Node in node.get_children():
		_measure(child, page, in_scroll or node is ScrollContainer)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
