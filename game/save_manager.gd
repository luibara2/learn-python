extends RefCounted
class_name SaveManager

const SAVES_ROOT := "user://saves/"
const GAME_JSON := "game.json"
const SAVE_VERSION := 2
const DEFAULT_SCRIPT_RES := "res://game/default_drone_script.txt"

static func _globalize(p: String) -> String:
	return ProjectSettings.globalize_path(p)


static func ensure_saves_root() -> void:
	DirAccess.make_dir_recursive_absolute(_globalize(SAVES_ROOT))


static func slot_path(slot_id: String) -> String:
	return SAVES_ROOT.path_join(slot_id)


static func default_drone_source() -> String:
	return FileAccess.get_file_as_string(DEFAULT_SCRIPT_RES)


static func game_json_path(slot_id: String) -> String:
	return slot_path(slot_id).path_join(GAME_JSON)


static func list_slots() -> PackedStringArray:
	ensure_saves_root()
	var out: PackedStringArray = PackedStringArray()
	var d: DirAccess = DirAccess.open(SAVES_ROOT)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if d.current_is_dir() and not n.begins_with("."):
			var gp: String = game_json_path(n)
			if FileAccess.file_exists(gp):
				out.append(n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


static func slot_exists(slot_id: String) -> bool:
	return FileAccess.file_exists(game_json_path(slot_id))


static func slot_folder_exists(slot_id: String) -> bool:
	return DirAccess.dir_exists_absolute(_globalize(slot_path(slot_id)))


static func unique_slot_id(base_name: String) -> String:
	var s: String = sanitize_slot_id(base_name)
	var candidate: String = s
	var n: int = 1
	while slot_folder_exists(candidate):
		n += 1
		candidate = "%s_%d" % [s, n]
	return candidate


static func sanitize_slot_id(name: String) -> String:
	var s: String = name.strip_edges()
	var b: String = ""
	for i in s.length():
		var c: String = s.substr(i, 1)
		if _is_slot_char_ok(c):
			b += c
	var r: String = b.strip_edges()
	if r.is_empty():
		r = "save"
	return r


static func _is_slot_char_ok(c: String) -> bool:
	if c.length() != 1:
		return false
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-"


static func sanitize_py_basename(name: String) -> String:
	var s: String = name.strip_edges().to_lower()
	var b: String = ""
	for i in s.length():
		var c: String = s.substr(i, 1)
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			b += c
	if b.is_empty():
		b = "script"
	return b


static func unique_py_filename(slot_id: String, basename: String) -> String:
	var base: String = sanitize_py_basename(basename)
	var fn: String = base + ".py"
	var n: int = 2
	while FileAccess.file_exists(slot_path(slot_id).path_join(fn)):
		fn = "%s_%d.py" % [base, n]
		n += 1
	return fn


static func delete_slot(slot_id: String) -> bool:
	var abs_base: String = _globalize(slot_path(slot_id))
	if not DirAccess.dir_exists_absolute(abs_base):
		return false
	return _remove_dir_recursive(abs_base)


static func _remove_dir_recursive(abs_path: String) -> bool:
	var d: DirAccess = DirAccess.open(abs_path)
	if d == null:
		return false
	d.list_dir_begin()
	var fn: String = d.get_next()
	while fn != "":
		if fn == "." or fn == "..":
			fn = d.get_next()
			continue
		var p: String = abs_path.path_join(fn)
		if d.current_is_dir():
			_remove_dir_recursive(p)
		else:
			DirAccess.remove_absolute(p)
		fn = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(abs_path)
	return true


static func read_py(slot_id: String, filename: String) -> String:
	var p: String = slot_path(slot_id).path_join(filename)
	if not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p)


static func write_py(slot_id: String, filename: String, source: String) -> bool:
	var f: FileAccess = FileAccess.open(slot_path(slot_id).path_join(filename), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(source)
	f.close()
	return true


static func delete_py(slot_id: String, filename: String) -> void:
	var p: String = slot_path(slot_id).path_join(filename)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(_globalize(p))


static func rename_py(slot_id: String, old_filename: String, new_filename: String) -> bool:
	var o: String = slot_path(slot_id).path_join(old_filename)
	var n: String = slot_path(slot_id).path_join(new_filename)
	if not FileAccess.file_exists(o) or FileAccess.file_exists(n):
		return false
	var txt: String = FileAccess.get_file_as_string(o)
	if not write_py(slot_id, new_filename, txt):
		return false
	delete_py(slot_id, old_filename)
	return true


static func create_slot(slot_id: String, default_script: String = "") -> bool:
	ensure_saves_root()
	var sp: String = slot_path(slot_id)
	var abs_sp: String = _globalize(sp)
	var src: String = default_script
	if src.is_empty():
		src = default_drone_source()
	if DirAccess.dir_exists_absolute(abs_sp):
		return false
	var err: Error = DirAccess.make_dir_recursive_absolute(abs_sp)
	if err != OK:
		return false
	var main_py: String = "main.py"
	if not write_py(slot_id, main_py, src):
		return false
	var node_id: String = new_node_id()
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"inventory": {"hay": 0, "wheat": 0, "carrot": 0},
		"drone_x": 0,
		"drone_y": 7,
		"farm": _default_farm_dict(),
		"nodes": [
			{
				"id": node_id,
				"name": "main",
				"filename": main_py,
				"pos": [28.0, 72.0],
				"collapsed": false,
				"panel_w": 480,
				"panel_h": 340,
			}
		],
	}
	return write_game_json(slot_id, data)


static func _default_farm_dict() -> Dictionary:
	var fs: FarmState = FarmState.new(8, 8)
	return fs.to_save_dict()


static func new_node_id() -> String:
	return "%d_%d" % [Time.get_ticks_msec(), randi() % 100000]


static func read_game_json(slot_id: String) -> Dictionary:
	var p: String = game_json_path(slot_id)
	if not FileAccess.file_exists(p):
		return {}
	var txt: String = FileAccess.get_file_as_string(p)
	var v: Variant = JSON.parse_string(txt)
	if v is Dictionary:
		return v
	return {}


static func write_game_json(slot_id: String, data: Dictionary) -> bool:
	data["version"] = SAVE_VERSION
	var f: FileAccess = FileAccess.open(game_json_path(slot_id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true
