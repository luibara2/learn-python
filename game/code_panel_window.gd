extends PanelContainer
class_name CodePanelWindow

const CONTENT := preload("res://ui/code_panel_content.tscn")

var setup_payload: Dictionary = {}
var game_session: Node

var node_id: String = ""
var py_filename: String = ""
var _ui: Control
var _collapsed: bool = false


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
	position = Vector2(px, py)
	custom_minimum_size = Vector2(pw, ph)
	size = custom_minimum_size
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
	var sz: Vector2 = size if size.length_squared() > 10.0 else custom_minimum_size
	return {
		"id": node_id,
		"name": (_ui.get_display_name() if _ui != null else _display_name_from_filename(py_filename)),
		"filename": py_filename,
		"pos": [position.x, position.y],
		"collapsed": _collapsed,
		"panel_w": int(roundf(sz.x)),
		"panel_h": int(roundf(sz.y)),
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


func _on_stop_pressed() -> void:
	if game_session:
		game_session.stop_interpreter()


func _on_close_pressed() -> void:
	if game_session:
		game_session.request_close_panel(self)


func _on_minimize_pressed() -> void:
	_collapsed = not _collapsed
	if _ui:
		_ui.set_collapsed(_collapsed)


func _on_name_submitted(new_name: String) -> void:
	if game_session == null or new_name.is_empty():
		return
	game_session.rename_code_panel(self, new_name)


func _on_title_drag_relative(delta: Vector2) -> void:
	position += delta
	var pr: Control = get_parent() as Control
	if pr:
		position.x = clampf(position.x, -size.x + 40.0, pr.size.x - 40.0)
		position.y = clampf(position.y, 0.0, maxf(0.0, pr.size.y - 48.0))
