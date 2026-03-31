extends TextEdit
class_name PythonCodeEdit

## Fired for user edits only (not load/set_programmatic_text).
signal modified_by_user

var _programmatic: bool = false
var _applying_indent: bool = false
var _last_line_count: int = 0


func set_programmatic_text(t: String) -> void:
	_programmatic = true
	text = t
	_programmatic = false
	_last_line_count = get_line_count()


func _ready() -> void:
	text_changed.connect(_on_text_changed)
	_last_line_count = get_line_count()


func _on_text_changed() -> void:
	if _programmatic or _applying_indent:
		return
	var n: int = get_line_count()
	var line_count_increased: bool = n > _last_line_count
	_last_line_count = n
	modified_by_user.emit()
	## Only indent right after Enter (new line). Otherwise backspace on the auto-tab
	## leaves an empty line and we'd re-insert the tab every time.
	if line_count_increased:
		_apply_newline_indent_next_frame()


## Enter is handled inside TextEdit before our script can intercept it. Wait one frame so
## caret + lines match the newline, then:
## - After a line ending with ":", indent one level deeper (same leading ws + tab).
## - After any other non-empty line, copy the previous line's leading whitespace.
func _apply_newline_indent_next_frame() -> void:
	await get_tree().process_frame
	if _programmatic or _applying_indent or not is_inside_tree():
		return
	var cl: int = get_caret_line()
	if cl <= 0:
		return
	var prev: String = get_line(cl - 1).replace("\r", "")
	var cur: String = get_line(cl).replace("\r", "")
	if not cur.is_empty():
		return
	var prev_lead: String = _leading_whitespace(prev)
	var prev_stripped: String = prev.strip_edges()
	var indent: String = ""
	if prev_stripped.ends_with(":"):
		indent = prev_lead + "\t"
	elif prev_stripped.is_empty():
		## Previous line is empty or whitespace-only: keep column / block depth.
		indent = prev_lead
	else:
		## Normal line: next line starts aligned with this one.
		indent = prev_lead
	if indent.is_empty():
		return
	_applying_indent = true
	insert_text_at_caret(indent)
	_applying_indent = false


func _leading_whitespace(s: String) -> String:
	var n := s.length()
	var i := 0
	while i < n:
		var ch := s[i]
		if ch == " " or ch == "\t":
			i += 1
		else:
			break
	return s.substr(0, i)
