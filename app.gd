extends Node

var _settings: SettingsStore = SettingsStore.new()

@onready var _main_menu: Control = $CanvasLayer/MainMenu
@onready var _slot_panel: Control = $CanvasLayer/SlotPanel
@onready var _options_panel: Control = $CanvasLayer/OptionsPanel
@onready var _game_world: Control = $GameWorld

@onready var _slot_list: ItemList = %SlotList
@onready var _new_save_name: LineEdit = %NewSaveName
@onready var _menu_log_text: TextEdit = %MenuLogText


func _ready() -> void:
	_settings.load_settings()
	_game_world.visible = false
	_game_world.requested_exit_to_menu.connect(_on_exit_to_menu)
	_wire_main_menu()
	_wire_slot_panel()
	_wire_options_panel()
	_slot_panel.visible = false
	_options_panel.visible = false


func _wire_main_menu() -> void:
	_main_menu.get_node("Center/VBox/StartBtn").pressed.connect(_on_main_start)
	_main_menu.get_node("Center/VBox/LoadBtn").pressed.connect(_on_main_load)
	_main_menu.get_node("Center/VBox/SaveBtn").pressed.connect(_on_main_save)
	_main_menu.get_node("Center/VBox/OptionsBtn").pressed.connect(_on_main_options)
	_main_menu.get_node("Center/VBox/QuitBtn").pressed.connect(func(): get_tree().quit())


func _wire_slot_panel() -> void:
	_slot_panel.get_node("Center/VBox/BackBtn").pressed.connect(_hide_slot_panel)
	_slot_panel.get_node("Center/VBox/HBoxLoad/LoadBtn").pressed.connect(_slot_load_selected)
	_slot_panel.get_node("Center/VBox/HBoxNew/NewBtn").pressed.connect(_slot_new)
	_slot_panel.get_node("Center/VBox/HBoxDel/DeleteBtn").pressed.connect(_slot_delete_selected)


func _wire_options_panel() -> void:
	var fs: CheckButton = _options_panel.get_node("Center/VBox/FullscreenCheck") as CheckButton
	var fps: OptionButton = _options_panel.get_node("Center/VBox/FpsOption") as OptionButton
	var au: CheckButton = _options_panel.get_node("Center/VBox/AutosaveCheck") as CheckButton
	var close_btn: Button = _options_panel.get_node("Center/VBox/CloseOptsBtn") as Button
	fs.button_pressed = _settings.fullscreen
	au.button_pressed = _settings.autosave
	fps.clear()
	fps.add_item("Unlimited")
	fps.add_item("30")
	fps.add_item("60")
	fps.add_item("120")
	fps.select(_settings.fps_index)
	fs.toggled.connect(func(on: bool):
		_settings.set_fullscreen(on)
	)
	fps.item_selected.connect(func(idx: int):
		_settings.set_fps_index(idx)
	)
	au.toggled.connect(func(on: bool):
		_settings.set_autosave(on)
	)
	close_btn.pressed.connect(func(): _options_panel.visible = false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _game_world.visible and _game_world.has_method("save_to_disk"):
			_game_world.save_to_disk()


func _on_main_start() -> void:
	SaveManager.ensure_saves_root()
	var slots: PackedStringArray = SaveManager.list_slots()
	if slots.is_empty():
		_show_slot_panel()
		return
	var use_slot: String = _settings.last_slot
	if use_slot.is_empty() or not SaveManager.slot_exists(use_slot):
		use_slot = slots[0]
	_begin_play(use_slot)


func _on_main_load() -> void:
	_show_slot_panel()


func _on_main_save() -> void:
	if not _game_world.visible:
		return
	if _game_world.has_method("save_to_disk"):
		_game_world.save_to_disk()


func _on_main_options() -> void:
	_options_panel.visible = true


func _show_slot_panel() -> void:
	_slot_panel.visible = true
	_refresh_slot_list()


func _hide_slot_panel() -> void:
	_slot_panel.visible = false


func _refresh_slot_list() -> void:
	_slot_list.clear()
	for s in SaveManager.list_slots():
		_slot_list.add_item(s)


func _slot_load_selected() -> void:
	var sel: PackedInt32Array = _slot_list.get_selected_items()
	if sel.is_empty():
		return
	var name: String = _slot_list.get_item_text(sel[0])
	_hide_slot_panel()
	_begin_play(name)


func _slot_new() -> void:
	var raw: String = _new_save_name.text
	var sid: String = SaveManager.unique_slot_id(raw)
	if not SaveManager.create_slot(sid):
		push_warning("Could not create save folder.")
		return
	_new_save_name.text = ""
	_refresh_slot_list()
	_hide_slot_panel()
	_begin_play(sid)


func _slot_delete_selected() -> void:
	var sel: PackedInt32Array = _slot_list.get_selected_items()
	if sel.is_empty():
		return
	var name: String = _slot_list.get_item_text(sel[0])
	SaveManager.delete_slot(name)
	_refresh_slot_list()


func _begin_play(slot_name: String) -> void:
	_settings.set_last_slot(slot_name)
	_main_menu.visible = false
	_slot_panel.visible = false
	_options_panel.visible = false
	_game_world.visible = true
	_game_world.start_session(slot_name, _settings)


func _on_exit_to_menu() -> void:
	var log: String = ""
	if _game_world.has_method("get_session_log"):
		log = _game_world.get_session_log()
	if _game_world.has_method("clear_error_notification"):
		_game_world.clear_error_notification()
	_game_world.end_session()
	_game_world.visible = false
	_main_menu.visible = true
	if _menu_log_text != null:
		_menu_log_text.text = log
