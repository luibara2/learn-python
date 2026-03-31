extends PanelContainer
class_name CodePanelWindow

const CONTENT := preload("res://ui/code_panel_content.tscn")

var setup_payload: Dictionary = {}
var game_session: Node

var node_id: String = ""
var py_filename: String = ""
var _ui: Control
var _collapsed: bool = false
## Full panel size when expanded; kept while collapsed for save/restore.
var _expanded_size: Vector2 = Vector2(480, 340)
var world_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	if setup_payload.is_empty():
		return
	_apply_payload()
	_build_ui()


func _apply_payload() -> void:
	node_id = str(setup_payload.get("id", ""))
	py_filename = str(setup_payload.get("filename", "main.py"))
	var pw: int = int(setup_payload.get("panel_w", 480))
	var ph: int = int(setup_payload.get("panel_h", 340))
	var pos_arr: Variant = setup_payload.get("pos", [40, 88])
	var px: float = 40.0
	var py: float = 88.0
	if pos_arr is Array and (pos_arr as Array).size() >= 2:
		px = float((pos_arr as Array)[0])
		py = float((pos_arr as Array)[1])
	world_pos = Vector2(px, py)
	position = world_pos
	_expanded_size = Vector2(float(pw), float(ph))
	custom_minimum_size = _expanded_size
	size = _expanded_size
	_collapsed = bool(setup_payload.get("collapsed", false))
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build_ui() -> void:
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.offset_left = 4
	mc.offset_top = 4
	mc.offset_right = -4
	mc.offset_bottom = -4
	add_child(mc)

	var ui_root: Control = CONTENT.instantiate()
	mc.add_child(ui_root)
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)

	_ui = ui_root
	var slot: String = game_session.slot_id
	ui_root.set_source(SaveManager.read_py(slot, py_filename))
	ui_root.set_display_name(_display_name_from_filename(py_filename))
	ui_root.set_collapsed(_collapsed)
	ui_root.set_running(false)

	ui_root.run_pressed.connect(_on_run_pressed)
	ui_root.stop_pressed.connect(_on_stop_pressed)
	ui_root.close_pressed.connect(_on_close_pressed)
	ui_root.minimize_pressed.connect(_on_minimize_pressed)
	ui_root.name_submitted.connect(_on_name_submitted)
	ui_root.title_drag_start.connect(func(_p: Vector2) -> void: move_to_front())
	ui_root.title_drag_relative.connect(_on_title_drag_relative)
	ui_root.code_changed_by_user.connect(_on_code_changed_by_user)

	if _collapsed:
		call_deferred("_sync_window_size_to_collapse_state")


func _sync_window_size_to_collapse_state() -> void:
	if _ui == null:
		return
	if _collapsed:
		var inner_h: float = _ui.get_collapsed_inner_height()
		var h: float = maxf(inner_h + 8.0, 28.0)
		custom_minimum_size = Vector2(_expanded_size.x, h)
		size = custom_minimum_size
	else:
		custom_minimum_size = _expanded_size
		size = _expanded_size


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			move_to_front()


func _display_name_from_filename(fn: String) -> String:
	return fn.get_basename()


func refresh_name_label() -> void:
	if _ui:
		_ui.set_display_name(_display_name_from_filename(py_filename))


func to_save_node_dict() -> Dictionary:
	var w: int
	var h: int
	if _collapsed:
		w = int(roundf(_expanded_size.x))
		h = int(roundf(_expanded_size.y))
	else:
		var sz: Vector2 = size if size.length_squared() > 10.0 else custom_minimum_size
		w = int(roundf(sz.x))
		h = int(roundf(sz.y))
	return {
		"id": node_id,
		"name": (_ui.get_display_name() if _ui != null else _display_name_from_filename(py_filename)),
		"filename": py_filename,
		"pos": [world_pos.x, world_pos.y],
		"collapsed": _collapsed,
		"panel_w": w,
		"panel_h": h,
	}


func get_code_source() -> String:
	if _ui == null:
		return ""
	return _ui.get_source()


func set_run_buttons_busy(running: bool) -> void:
	if _ui:
		_ui.set_running(running)


func _on_run_pressed() -> void:
	if game_session:
		game_session.run_panel(self)


func _on_code_changed_by_user() -> void:
	if game_session:
		game_session.stop_if_busy_from_code_edit()


func _on_stop_pressed() -> void:
	if game_session:
		game_session.stop_interpreter()


func _on_close_pressed() -> void:
	if game_session:
		game_session.request_close_panel(self)


func _on_minimize_pressed() -> void:
	if not _collapsed:
		_expanded_size = Vector2(size.x, size.y)
	_collapsed = not _collapsed
	if _ui:
		_ui.set_collapsed(_collapsed)
	_sync_window_size_to_collapse_state()


func _on_name_submitted(new_name: String) -> void:
	if game_session == null or new_name.is_empty():
		return
	game_session.rename_code_panel(self, new_name)


func _on_title_drag_relative(delta: Vector2) -> void:
	var zoom: float = 1.0
	if game_session != null:
		zoom = maxf(0.001, game_session.get_world_zoom())
	world_pos += delta / zoom
	position = world_pos


func apply_camera_transform(camera_px: Vector2, zoom: float, zoom_pivot: Vector2) -> void:
	var z: float = maxf(0.001, zoom)
	scale = Vector2(z, z)
	position = world_pos * z - camera_px + zoom_pivot * (1.0 - z)
