class_name MeyuiSaveManager
extends RefCounted
## JSON only: no Variant deserialization, scripts, Resources or executable content.
## The previous valid save is retained before the final atomic rename.

const VERSION: int = 2
const SLOT_COUNT: int = 3
const MAX_BYTES: int = 4 * 1024 * 1024
const MAX_NODES: int = 120000
const MAX_DEPTH: int = 40
var storage_root: String
var _node_count: int = 0


func _init(directory: String = "user://saves") -> void:
	storage_root = ProjectSettings.globalize_path(directory).simplify_path()


func save_slot(slot: int, state: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	if not _valid_slot(slot):
		return _failure("Slot inválido.")
	if _read(_path(slot), slot).get("unsupported_version", false):
		return _failure("Este slot pertence a uma versão mais recente; escolha outro slot.")
	_node_count = 0
	if state.is_empty() or not _safe_json(state) or not _safe_json(metadata) or not _valid_state(state):
		return _failure("A partida contém dados inválidos.")
	if DirAccess.make_dir_recursive_absolute(storage_root) != OK:
		return _failure("Não foi possível criar a pasta de saves.")
	var now: String = Time.get_datetime_string_from_system(true)
	var safe_metadata: Dictionary = metadata.duplicate(true)
	safe_metadata["date"] = now
	var payload: Dictionary = {
		"slot": slot, "saved_at": now, "saved_unix": Time.get_unix_time_from_system(),
		"state": state, "metadata": safe_metadata,
	}
	var body: String = JSON.stringify(payload, "", true, true)
	var encoded: String = JSON.stringify({
		"format": "meyui-run", "version": VERSION, "body": body, "checksum": body.sha256_text(),
	})
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return _failure("A partida excede o tamanho máximo de save.")
	var path: String = _path(slot)
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("Não foi possível gravar o save temporário.")
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or not _read(temporary, slot).get("ok", false):
		return _failure("Falha ao verificar o save; a partida anterior foi preservada.")
	# A damaged primary must never replace a healthy backup.
	if _read(path, slot).get("ok", false):
		if DirAccess.copy_absolute(path, path + ".bak.tmp") != OK:
			return _failure("Falha ao preservar o backup; o save anterior foi mantido.")
		if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			return _failure("Falha ao atualizar o backup; o save anterior foi mantido.")
	if DirAccess.rename_absolute(temporary, path) != OK:
		return _failure("Falha ao concluir o save; o arquivo temporário pode ser recuperado.")
	return {"ok": true, "error": "", "metadata": safe_metadata, "slot": slot}


func load_slot(slot: int) -> Dictionary:
	if not _valid_slot(slot):
		return _failure("Slot inválido.")
	var path: String = _path(slot)
	var primary: Dictionary = _read(path, slot)
	if primary.get("ok", false):
		primary["recovered"] = false
		return primary
	# Future saves are left untouched; silently loading an older backup would roll
	# back a valid newer game after opening it with an older executable.
	if primary.get("unsupported_version", false):
		return primary
	for suffix in [".bak", ".tmp"]:
		var recovered: Dictionary = _read(path + suffix, slot)
		if recovered.get("ok", false):
			recovered["recovered"] = true
			recovered["recovery_source"] = "backup" if suffix == ".bak" else "temporary"
			return recovered
	return primary


func list_slots() -> Array:
	var result: Array = []
	for slot in range(1, SLOT_COUNT + 1):
		var loaded: Dictionary = load_slot(slot)
		var path: String = _path(slot)
		result.append({
			"slot": slot, "exists": FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp"),
			"valid": loaded.get("ok", false), "metadata": loaded.get("metadata", {}),
			"saved_unix": loaded.get("saved_unix", 0.0), "recovered": loaded.get("recovered", false),
			"error": loaded.get("error", ""),
		})
	return result


func has_save() -> bool:
	return latest_slot() != 0


func latest_slot() -> int:
	var latest: int = 0
	var timestamp: float = -1.0
	for entry: Dictionary in list_slots():
		if entry.valid and float(entry.saved_unix) > timestamp:
			latest = int(entry.slot)
			timestamp = float(entry.saved_unix)
	return latest


func delete_slot(slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	var successful: bool = true
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = _path(slot) + suffix
		if FileAccess.file_exists(path):
			successful = DirAccess.remove_absolute(path) == OK and successful
	return successful


func _read(path: String, slot: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("Slot vazio.")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Não foi possível ler o save.")
	if file.get_length() > MAX_BYTES:
		file.close()
		return _failure("Save maior que o limite permitido.")
	var raw: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(raw) != OK or not json.data is Dictionary:
		return _failure("Save danificado.")
	var envelope: Dictionary = json.data
	var version_value: Variant = envelope.get("version", envelope.get("schema_version", 0))
	if not _integer_between(version_value, 1, 1000000):
		return _failure("Versão de save inválida.")
	var version: int = int(version_value)
	if version > VERSION:
		return {"ok": false, "error": "Este save exige uma versão mais recente do jogo.", "unsupported_version": true, "recovered": false}
	var payload: Dictionary
	if version == 1:
		# v1 was a plain JSON envelope; migrate in memory and only write on save.
		payload = envelope.duplicate(true)
		payload["slot"] = envelope.get("slot", slot)
		payload["metadata"] = envelope.get("metadata", {})
		payload["saved_unix"] = envelope.get("saved_unix", 0.0)
	else:
		if envelope.get("format", "") != "meyui-run" or not envelope.get("body") is String or not envelope.get("checksum") is String:
			return _failure("Estrutura de save inválida.")
		var body: String = envelope.body
		if body.sha256_text() != envelope.checksum:
			return _failure("A integridade do save não pôde ser confirmada.")
		var body_json: JSON = JSON.new()
		if body_json.parse(body) != OK or not body_json.data is Dictionary:
			return _failure("Conteúdo de save inválido.")
		payload = body_json.data
	_node_count = 0
	if not _safe_json(payload) or not _integer_between(payload.get("slot"), slot, slot):
		return _failure("Dados de save inválidos.")
	if not payload.get("state") is Dictionary or not payload.get("metadata") is Dictionary:
		return _failure("Partida incompleta no save.")
	if payload.state.is_empty() or not _valid_state(payload.state):
		return _failure("A partida salva possui valores inválidos.")
	var saved_unix: Variant = payload.get("saved_unix", 0.0)
	if not _number(saved_unix) or float(saved_unix) < 0.0:
		return _failure("Data do save inválida.")
	return {
		"ok": true, "error": "", "state": payload.state, "metadata": payload.metadata,
		"saved_unix": saved_unix, "slot": slot, "version": VERSION, "migrated": version < VERSION,
	}


func _valid_state(state: Dictionary) -> bool:
	for key in ["round", "round_number"]:
		if state.has(key) and not _integer_between(state[key], 1, 1000000000):
			return false
	for key in ["coins", "seconds", "play_time"]:
		if state.has(key) and (not _number(state[key]) or float(state[key]) < 0.0 or float(state[key]) > 1.0e18):
			return false
	for key in ["player", "dog", "director", "stats", "world", "perks"]:
		if state.has(key) and not state[key] is Dictionary:
			return false
	return true


func _safe_json(value: Variant, depth: int = 0) -> bool:
	_node_count += 1
	if _node_count > MAX_NODES or depth > MAX_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).length() <= 16384
		TYPE_ARRAY:
			if value.size() > 20000:
				return false
			for item in value:
				if not _safe_json(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 20000:
				return false
			for key in value:
				if not (key is String or key is StringName) or str(key).length() > 256 or not _safe_json(value[key], depth + 1):
					return false
			return true
	return false


func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _integer_between(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum


func _valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func _path(slot: int) -> String:
	return storage_root.path_join("slot_%d.json" % slot)


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "state": {}, "metadata": {}, "recovered": false}
