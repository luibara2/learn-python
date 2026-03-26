extends Control

const SAVE_PATH := "user://farm_autosave.json"
const AUTOSAVE_INTERVAL_SEC := 10.0

const _Tokenizer := preload("res://script_lang/tokenizer.gd")
const _Parser := preload("res://script_lang/parser.gd")
const _Interpreter := preload("res://script_lang/interpreter.gd")

@onready var _code: TextEdit = %CodeEdit
@onready var _out: TextEdit = %Output
@onready var _farm_view: FarmView = %FarmView
@onready var _run_btn: Button = %RunBtn
@onready var _stop_btn: Button = %StopBtn
@onready var _inv_label: Label = %InventoryLabel

var _farm: FarmState
var _drone: DroneActor
var _interp: RefCounted
var _busy: bool = false
var _inventory: Dictionary = {"hay": 0, "wheat": 0, "carrot": 0}
var _autosave_elapsed: float = 0.0


func _ready() -> void:
	_farm = FarmState.new(8, 8)
	_drone = DroneActor.new()
	_drone.bind(_farm, _farm.drone_start_pos())
	_farm_view.setup(_farm, _drone.grid_pos)

	_interp = _Interpreter.new()
	_interp.farm = _farm
	_interp.drone = _drone
	_interp.farm_view = _farm_view
	_interp.host = self
	_interp.harvest_counts = _inventory
	_interp.log_line.connect(_on_log_line)
	_interp.finished.connect(_on_finished)

	_run_btn.pressed.connect(_on_run)
	_stop_btn.pressed.connect(_on_stop)

	var loaded: bool = _load_game()
	if not loaded and _code.text.strip_edges() == "":
		_code.text = DEFAULT_SCRIPT

	_refresh_inventory_ui()


func _process(delta: float) -> void:
	if _farm != null:
		_farm.process_growth(delta)
		_farm_view.queue_redraw()
	_refresh_inventory_ui()

	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL_SEC:
		_autosave_elapsed = 0.0
		_save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


func _save_game() -> void:
	if _farm == null or _drone == null or _code == null:
		return
	var data: Dictionary = {
		"version": 1,
		"inventory": {
			"hay": int(_inventory.get("hay", 0)),
			"wheat": int(_inventory.get("wheat", 0)),
			"carrot": int(_inventory.get("carrot", 0)),
		},
		"code": _code.text,
		"drone_x": _drone.grid_pos.x,
		"drone_y": _drone.grid_pos.y,
		"farm": _farm.to_save_dict(),
	}
	var json_text: String = JSON.stringify(data)
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Autosave: could not write %s" % SAVE_PATH)
		return
	f.store_string(json_text)
	f.close()


func _load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var json_text: String = FileAccess.get_file_as_string(SAVE_PATH)
	if json_text.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	if int(d.get("version", 0)) < 1:
		return false

	var inv: Variant = d.get("inventory", {})
	if inv is Dictionary:
		var id: Dictionary = inv
		for k in ["hay", "wheat", "carrot"]:
			if id.has(k):
				_inventory[k] = int(id[k])

	if d.has("code") and d["code"] is String:
		_code.text = d["code"]

	var farm_d: Variant = d.get("farm")
	if not farm_d is Dictionary:
		return false
	if not _farm.apply_save_dict(farm_d):
		return false

	var dx: int = int(d.get("drone_x", _farm.drone_start_pos().x))
	var dy: int = int(d.get("drone_y", _farm.drone_start_pos().y))
	_drone.grid_pos = Vector2i(dx, dy)
	if not _farm.in_bounds(_drone.grid_pos):
		_drone.snap_to_start()
	_farm_view.set_drone_cell(_drone.grid_pos)
	_farm_view.queue_redraw()
	return true


func _refresh_inventory_ui() -> void:
	if _inv_label == null:
		return
	_inv_label.text = "Hay: %d   Wheat: %d   Carrot: %d" % [
		int(_inventory.get("hay", 0)),
		int(_inventory.get("wheat", 0)),
		int(_inventory.get("carrot", 0)),
	]


const DEFAULT_SCRIPT := """# Till, plant, harvest — then walk east and repeat once.
till()
plant(Entities.WHEAT)
harvest()

move('east')

if get_ground() == Grounds.GRASS:
	till()
	plant(Entities.WHEAT)
"""


func _on_log_line(s: String) -> void:
	_out.text += s + "\n"


func _on_finished(ok: bool, message: String) -> void:
	_busy = false
	_run_btn.disabled = false
	_out.text += "[%s] %s\n" % ["ok" if ok else "error", message]


func _on_stop() -> void:
	_interp.stop()


func _on_run() -> void:
	if _busy:
		return
	_busy = true
	_run_btn.disabled = true
	_out.text = ""

	var tz: RefCounted = _Tokenizer.new()
	var tokens: Array = tz.tokenize(_code.text)
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


func _finish_err(msg: String) -> void:
	_busy = false
	_run_btn.disabled = false
	_out.text = msg + "\n"
