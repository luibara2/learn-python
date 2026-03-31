extends Control

signal requested_exit_to_menu

const _Tokenizer := preload("res://script_lang/tokenizer.gd")
const _Parser := preload("res://script_lang/parser.gd")
const _Interpreter := preload("res://script_lang/interpreter.gd")

const AUTOSAVE_INTERVAL_SEC := 10.0

var slot_id: String = ""
var _settings: SettingsStore

var _farm: FarmState
var _drone: DroneActor
var _interp: RefCounted
var _busy: bool = false
var _inventory: Dictionary = {"hay": 0, "wheat": 0, "carrot": 0}
var _autosave_elapsed: float = 0.0
var _panels: Array[CodePanelWindow] = []

@onready var code_windows_root: Control = $VBoxRoot/MainArea/CodeWindowsRoot
@onready var farm_view: FarmView = $VBoxRoot/MainArea/FarmColumn/FarmHolder/FarmView as FarmView

@onready var inv_label: Label = %InvLabel
@onready var save_btn: Button = %SaveBtn
@onready var menu_btn: Button = %MenuBtn
@onready var add_node_btn: Button = %AddNodeBtn
@onready var error_warn: Label = %ErrorWarn

## Mirrors former bottom output panel; shown on main menu after exit.
var _session_log: String = ""
var _error_notification: bool = false


func _ready() -> void:
	save_btn.pressed.connect(_on_save_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	add_node_btn.pressed.connect(create_code_node)
	code_windows_root.gui_input.connect(_on_code_windows_root_gui_input)
	visible = false
	set_process(false)


func get_session_log() -> String:
	return _session_log


func clear_error_notification() -> void:
	_error_notification = false
	_update_error_warn()


func start_session(p_slot: String, settings: SettingsStore) -> void:
	slot_id = p_slot
	_settings = settings
	_session_log = ""
	_error_notification = false
	_update_error_warn()
	visible = true
	set_process(true)
	if not _load_slot_data():
		visible = false
		set_process(false)
		requested_exit_to_menu.emit()
		return
	_wire_interpreter()


func _on_code_windows_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			## Clicks on empty space (not on a panel) clear code-editor focus.
			get_viewport().gui_release_focus()


func end_session() -> void:
	set_process(false)
	visible = false
	for c in code_windows_root.get_children():
		c.queue_free()
	_panels.clear()
	_farm = null
	_interp = null


func _wire_interpreter() -> void:
	_interp = _Interpreter.new()
	_interp.farm = _farm
	_interp.drone = _drone
	_interp.farm_view = _farm_view_node()
	_interp.host = self
	_interp.harvest_counts = _inventory
	_interp.log_line.connect(_on_log_line)
	_interp.finished.connect(_on_finished)


func _farm_view_node() -> FarmView:
	return farm_view


func _load_slot_data() -> bool:
	var data: Dictionary = SaveManager.read_game_json(slot_id)
	if data.is_empty():
		push_error("Empty save: %s" % slot_id)
		return false

	_farm = FarmState.new(8, 8)
	_drone = DroneActor.new()
	_drone.bind(_farm, _farm.drone_start_pos())

	var inv: Variant = data.get("inventory", {})
	if inv is Dictionary:
		for k in ["hay", "wheat", "carrot"]:
			if (inv as Dictionary).has(k):
				_inventory[k] = int((inv as Dictionary)[k])

	var farm_d: Variant = data.get("farm")
	if farm_d is Dictionary:
		_farm.apply_save_dict(farm_d)

	var dx: int = int(data.get("drone_x", _farm.drone_start_pos().x))
	var dy: int = int(data.get("drone_y", _farm.drone_start_pos().y))
	_drone.grid_pos = Vector2i(dx, dy)
	if not _farm.in_bounds(_drone.grid_pos):
		_drone.snap_to_start()

	var fv: FarmView = _farm_view_node()
	fv.setup(_farm, _drone.grid_pos)

	for c in code_windows_root.get_children():
		c.queue_free()
	_panels.clear()

	var nodes: Variant = data.get("nodes", [])
	if nodes is Array:
		for item in nodes as Array:
			if item is Dictionary:
				_spawn_code_panel(item as Dictionary)
	return true


func _spawn_code_panel(node_data: Dictionary) -> void:
	var panel := CodePanelWindow.new()
	panel.setup_payload = node_data.duplicate(true)
	panel.game_session = self
	code_windows_root.add_child(panel)
	_panels.append(panel)
	call_deferred("_sync_code_node_positions")


func create_code_node() -> void:
	var fn: String = SaveManager.unique_py_filename(slot_id, "node")
	SaveManager.write_py(slot_id, fn, SaveManager.default_drone_source())
	var n: int = _panels.size()
	var fv: FarmView = _farm_view_node()
	var cam_px: Vector2 = fv.get_camera_screen_offset()
	var zoom: float = maxf(0.001, fv.get_camera_zoom())
	var zoom_pivot: Vector2 = code_windows_root.size * 0.5
	var spawn_screen: Vector2 = Vector2(24.0 + n * 28.0, 56.0 + n * 32.0)
	var spawn_world: Vector2 = (spawn_screen - zoom_pivot * (1.0 - zoom) + cam_px) / zoom
	var node_data: Dictionary = {
		"id": SaveManager.new_node_id(),
		"name": fn.get_basename(),
		"filename": fn,
		"pos": [spawn_world.x, spawn_world.y],
		"collapsed": false,
		"panel_w": 480,
		"panel_h": 340,
	}
	_spawn_code_panel(node_data)
	save_to_disk()


func _process(delta: float) -> void:
	if _farm == null:
		return
	_farm.process_growth(delta)
	var fv: FarmView = _farm_view_node()
	fv.queue_redraw()
	_sync_code_node_positions()
	_refresh_inventory_ui()

	if _settings != null and _settings.autosave:
		_autosave_elapsed += delta
		if _autosave_elapsed >= AUTOSAVE_INTERVAL_SEC:
			_autosave_elapsed = 0.0
			save_to_disk()


func _sync_code_node_positions() -> void:
	var fv: FarmView = _farm_view_node()
	if fv == null:
		return
	var cam_px: Vector2 = fv.get_camera_screen_offset()
	var zoom: float = fv.get_camera_zoom()
	var zoom_pivot: Vector2 = code_windows_root.size * 0.5
	for p in _panels:
		if p != null:
			p.apply_camera_transform(cam_px, zoom, zoom_pivot)


func get_world_zoom() -> float:
	var fv: FarmView = _farm_view_node()
	if fv == null:
		return 1.0
	return fv.get_camera_zoom()


func request_close_panel(panel: CodePanelWindow) -> void:
	if _panels.size() <= 1:
		_append_session_line("Cannot delete the last code node.", true)
		return
	var idx: int = _panels.find(panel)
	if idx < 0:
		return
	SaveManager.delete_py(slot_id, panel.py_filename)
	_panels.remove_at(idx)
	panel.queue_free()
	save_to_disk()


func rename_code_panel(panel: CodePanelWindow, new_name: String) -> void:
	var base: String = SaveManager.sanitize_py_basename(new_name)
	if base.is_empty():
		return
	var new_fn: String = base + ".py"
	if new_fn == panel.py_filename:
		return
	var taken: bool = false
	for p in _panels:
		if p != panel and p.py_filename == new_fn:
			taken = true
			break
	if taken:
		new_fn = SaveManager.unique_py_filename(slot_id, base)
	if not SaveManager.rename_py(slot_id, panel.py_filename, new_fn):
		_append_session_line("Could not rename script file.", true)
		return
	panel.py_filename = new_fn
	panel.refresh_name_label()
	save_to_disk()


func run_panel(panel: CodePanelWindow) -> void:
	if _busy:
		return
	_busy = true
	for p in _panels:
		p.set_run_buttons_busy(true)
	_session_log = ""
	_error_notification = false
	_update_error_warn()

	var src: String = panel.get_code_source()
	SaveManager.write_py(slot_id, panel.py_filename, src)

	var tz: RefCounted = _Tokenizer.new()
	var tokens: Array = tz.tokenize(src)
	if tokens.is_empty():
		_finish_err("No tokens.")
		return
	if tokens[0].get("error", false):
		_finish_err("Line %d: %s" % [int(tokens[0].line), str(tokens[0].message)])
		return

	var pr: RefCounted = _Parser.new()
	var ast: Variant = pr.parse(tokens)
	if ast is Dictionary and ast.get("error", false):
		_finish_err("Line %d: %s" % [int(ast.line), str(ast.message)])
		return

	await _interp.run_program(ast as Dictionary)


func stop_interpreter() -> void:
	if _interp != null:
		_interp.stop()


func stop_if_busy_from_code_edit() -> void:
	if _busy:
		stop_interpreter()


func _finish_err(msg: String) -> void:
	_busy = false
	for p in _panels:
		p.set_run_buttons_busy(false)
	_append_session_line(msg, true)


func _on_log_line(s: String) -> void:
	_append_session_line(s, false)


func _on_finished(ok: bool, message: String) -> void:
	_busy = false
	for p in _panels:
		p.set_run_buttons_busy(false)
	var line: String = "[%s] %s" % ["ok" if ok else "error", message]
	_append_session_line(line, not ok)


func _append_session_line(s: String, is_error: bool) -> void:
	_session_log += s + "\n"
	if is_error:
		_error_notification = true
	_update_error_warn()


func _update_error_warn() -> void:
	if error_warn != null:
		error_warn.visible = _error_notification


func _refresh_inventory_ui() -> void:
	if inv_label == null:
		return
	inv_label.text = "Hay: %d   Wheat: %d   Carrot: %d" % [
		int(_inventory.get("hay", 0)),
		int(_inventory.get("wheat", 0)),
		int(_inventory.get("carrot", 0)),
	]


func build_save_dict() -> Dictionary:
	var nodes: Array = []
	for p in _panels:
		nodes.append(p.to_save_node_dict())
	return {
		"version": SaveManager.SAVE_VERSION,
		"inventory": {
			"hay": int(_inventory.get("hay", 0)),
			"wheat": int(_inventory.get("wheat", 0)),
			"carrot": int(_inventory.get("carrot", 0)),
		},
		"drone_x": _drone.grid_pos.x,
		"drone_y": _drone.grid_pos.y,
		"farm": _farm.to_save_dict(),
		"nodes": nodes,
	}


func save_to_disk() -> void:
	if slot_id.is_empty() or _farm == null:
		return
	for p in _panels:
		SaveManager.write_py(slot_id, p.py_filename, p.get_code_source())
	SaveManager.write_game_json(slot_id, build_save_dict())


func _on_save_pressed() -> void:
	save_to_disk()
	_append_session_line("(saved)", false)


func _on_menu_pressed() -> void:
	save_to_disk()
	_append_session_line("(saved)", false)
	requested_exit_to_menu.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if visible and not slot_id.is_empty():
			save_to_disk()
