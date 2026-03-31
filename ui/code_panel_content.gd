extends Control
## 2D UI hosted inside a SubViewport for one code node.

signal run_pressed
signal stop_pressed
signal close_pressed
signal minimize_pressed
signal title_drag_start(local_pos: Vector2)
## Screen-space delta while dragging the title strip (2D panels only).
signal title_drag_relative(delta: Vector2)
signal name_submitted(new_display_name: String)
signal code_changed_by_user

@onready var drag_handle: ColorRect = %DragHandle
@onready var title_bar: PanelContainer = %TitleBar
@onready var name_edit: LineEdit = %NameEdit
@onready var code_edit: PythonCodeEdit = %CodeEdit
@onready var run_btn: Button = %RunBtn
@onready var stop_btn: Button = %StopBtn
@onready var min_btn: Button = %MinBtn
@onready var close_btn: Button = %CloseBtn
@onready var body: VBoxContainer = %Body

var _dragging_title: bool = false


func _ready() -> void:
	run_btn.pressed.connect(func(): run_pressed.emit())
	stop_btn.pressed.connect(func(): stop_pressed.emit())
	min_btn.pressed.connect(func(): minimize_pressed.emit())
	close_btn.pressed.connect(func(): close_pressed.emit())
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_on_name_focus_out)
	drag_handle.gui_input.connect(_on_drag_handle_gui)
	code_edit.modified_by_user.connect(func(): code_changed_by_user.emit())


func set_display_name(n: String) -> void:
	name_edit.text = n


func get_display_name() -> String:
	return name_edit.text.strip_edges()


func set_source(text: String) -> void:
	code_edit.set_programmatic_text(text)


func get_source() -> String:
	return code_edit.text


func set_running(running: bool) -> void:
	run_btn.disabled = running
	stop_btn.disabled = not running


func set_collapsed(c: bool) -> void:
	body.visible = not c


func get_collapsed_inner_height() -> float:
	if title_bar != null:
		return title_bar.get_combined_minimum_size().y
	return 36.0


func append_output(line: String) -> void:
	pass


func _on_name_submitted(new_text: String) -> void:
	name_submitted.emit(new_text.strip_edges())


func _on_name_focus_out() -> void:
	name_submitted.emit(name_edit.text.strip_edges())


func _on_drag_handle_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging_title = true
				title_drag_start.emit(mb.position)
			else:
				_dragging_title = false
	elif event is InputEventMouseMotion and _dragging_title:
		var mm: InputEventMouseMotion = event
		title_drag_relative.emit(mm.relative)
