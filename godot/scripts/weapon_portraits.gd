extends Node

## One off-screen inspection viewport feeds a bounded portrait cache.
## Backpack cards never allocate their own 3D world, lights or camera.
const Preview = preload("res://scripts/preview_stage.gd")
var cache: Dictionary = {}
var pending: Array[Dictionary] = []
var stage: Control
var busy := false

static func request(item: Dictionary, stats: Dictionary, receiver: Control) -> void:
	if item.is_empty() or DisplayServer.get_name() == "headless" or not receiver.is_inside_tree(): return
	var root := receiver.get_tree().root
	var service := root.get_node_or_null("WeaponPortraitCache")
	if service == null:
		service = load("res://scripts/weapon_portraits.gd").new()
		service.name = "WeaponPortraitCache"
		root.add_child(service)
	var attachment_ids: Array[String] = []
	for slot: String in preload("res://data/loot_data.gd").SLOTS:
		var attachment: Variant = item.attachments.get(slot, {})
		attachment_ids.append(str(attachment.get("id", "")) if attachment is Dictionary else str(attachment))
	var key := JSON.stringify([item.model_id, item.rarity, item.manufacturer, item.get("element", "none"), attachment_ids])
	if service.cache.has(key): receiver.call("set_portrait", service.cache[key])
	elif service.pending.size() < 96: service.pending.append({"key":key, "item":item.duplicate(true), "stats":stats.duplicate(true), "receiver":weakref(receiver)})

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	stage = Preview.new()
	add_child(stage)
	stage.position = Vector2(-10000,-10000)
	stage.custom_minimum_size = Vector2.ZERO
	stage.size = Vector2(320,144)
	stage.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for node: Node in stage.viewport.get_child(0).get_children():
		if node is MeshInstance3D: node.hide()

func _process(_delta: float) -> void:
	if busy or pending.is_empty(): return
	_render_next()

func _render_next() -> void:
	busy = true
	var entry: Dictionary = pending.pop_front()
	var receiver: Object = entry.receiver.get_ref()
	if not is_instance_valid(receiver):
		busy = false
		return
	if not cache.has(entry.key):
		stage.show_weapon(entry.item, entry.stats)
		stage.camera.size = 0.85
		stage.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var picture: Image = stage.viewport.get_texture().get_image()
		if not picture.is_empty():
			if cache.size() >= 64: cache.erase(cache.keys()[0])
			cache[entry.key] = ImageTexture.create_from_image(picture)
	if is_instance_valid(entry.receiver.get_ref()) and cache.has(entry.key): entry.receiver.get_ref().call("set_portrait", cache[entry.key])
	busy = false
