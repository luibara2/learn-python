extends RefCounted
class_name SettingsStore

const PATH := "user://settings.cfg"
const SEC := "settings"

var fullscreen: bool = false
var fps_index: int = 1
var autosave: bool = true
var last_slot: String = ""


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		apply_to_engine()
		return
	fullscreen = bool(cf.get_value(SEC, "fullscreen", false))
	fps_index = int(cf.get_value(SEC, "fps_index", 1))
	autosave = bool(cf.get_value(SEC, "autosave", true))
	last_slot = str(cf.get_value(SEC, "last_slot", ""))
	apply_to_engine()


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SEC, "fullscreen", fullscreen)
	cf.set_value(SEC, "fps_index", fps_index)
	cf.set_value(SEC, "autosave", autosave)
	cf.set_value(SEC, "last_slot", last_slot)
	cf.save(PATH)


func apply_to_engine() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	match fps_index:
		0:
			Engine.max_fps = 0
		1:
			Engine.max_fps = 30
		2:
			Engine.max_fps = 60
		3:
			Engine.max_fps = 120
		_:
			Engine.max_fps = 60


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_to_engine()
	save_settings()


func set_fps_index(idx: int) -> void:
	fps_index = clampi(idx, 0, 3)
	apply_to_engine()
	save_settings()


func set_autosave(on: bool) -> void:
	autosave = on
	save_settings()


func set_last_slot(slot_id: String) -> void:
	last_slot = slot_id
	save_settings()
