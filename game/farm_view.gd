extends Control
class_name FarmView

@export var tile_size: int = 56
@export var grid_width: int = 8
@export var grid_height: int = 8
## When on, draws a tilted isometric diamond grid. Off = straight top-down (N up, S down).
@export var isometric: bool = false
@export var show_compass_labels: bool = true
## Half-width of each tile diamond (horizontal extent from center to corner).
@export var iso_tile_w: float = 28.0
## Half-height of each tile diamond (vertical extent from center to top/bottom corner).
@export var iso_tile_h: float = 16.0
## Camera pan speed in world-tile units per second.
@export var pan_speed: float = 4.5
## Height of tile side faces for the cube look.
@export var iso_cube_h: float = 24.0
## Mouse wheel zoom step size.
@export var zoom_step: float = 0.08
@export var min_zoom: float = 0.6
@export var max_zoom: float = 1.8
var camera_zoom: float = 1.0

var farm: FarmState
var drone_grid: Vector2i = Vector2i.ZERO
var camera_world: Vector2 = Vector2.ZERO

const COL_GRASS := Color(0.35, 0.62, 0.32)
const COL_GRASS_DARK := Color(0.28, 0.52, 0.26)
const COL_SOIL := Color(0.45, 0.32, 0.22)
const COL_SOIL_DARK := Color(0.36, 0.26, 0.18)
const COL_GRASS_SIDE_L := Color(0.27, 0.49, 0.25)
const COL_GRASS_SIDE_R := Color(0.21, 0.42, 0.2)
const COL_SOIL_SIDE_L := Color(0.35, 0.24, 0.17)
const COL_SOIL_SIDE_R := Color(0.29, 0.2, 0.14)
const COL_WHEAT := Color(0.85, 0.75, 0.35)
const COL_HAY_GROW := Color(0.55, 0.72, 0.38)
const COL_HAY_READY := Color(0.82, 0.7, 0.28)
const COL_DRONE := Color(0.92, 0.45, 0.2)
const OUTLINE := Color(0.12, 0.1, 0.09)
const COMPASS_MARGIN := 22


func _ready() -> void:
	set_process(true)


func setup(p_farm: FarmState, start: Vector2i) -> void:
	farm = p_farm
	drone_grid = start
	camera_world = Vector2.ZERO
	camera_zoom = 1.0
	if isometric:
		var span: float = float(farm.width + farm.height)
		custom_minimum_size = Vector2(int(span * iso_tile_w + 64.0), int(span * iso_tile_h + iso_cube_h + 140.0))
	else:
		var pad: int = COMPASS_MARGIN * 2 + (16 if show_compass_labels else 0)
		custom_minimum_size = Vector2(
			farm.width * tile_size + pad,
			farm.height * tile_size + pad + (12 if show_compass_labels else 0)
		)
	queue_redraw()


func set_drone_cell(g: Vector2i) -> void:
	drone_grid = g
	queue_redraw()


func _process(delta: float) -> void:
	if farm == null:
		return
	if not _can_pan_camera():
		return

	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0

	if dir.is_zero_approx():
		return

	camera_world += dir.normalized() * pan_speed * delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if farm == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			## Clicking the map should leave the code editor so WASD pans again.
			get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	if farm == null:
		return
	if not _can_zoom_camera():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(camera_zoom + zoom_step)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(camera_zoom - zoom_step)
			get_viewport().set_input_as_handled()


func _can_pan_camera() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus == null:
		return true
	return not (focus is LineEdit or focus is TextEdit)


func _can_zoom_camera() -> bool:
	return _can_pan_camera()


func _set_zoom(z: float) -> void:
	var next: float = clampf(z, min_zoom, max_zoom)
	if is_equal_approx(next, camera_zoom):
		return
	camera_zoom = next
	queue_redraw()


func _iso_w() -> float:
	return iso_tile_w * camera_zoom


func _iso_h() -> float:
	return iso_tile_h * camera_zoom


func _cube_h() -> float:
	return iso_cube_h * camera_zoom


func _ortho_tile_px() -> float:
	return float(tile_size) * camera_zoom


func _project_iso(world: Vector2) -> Vector2:
	return Vector2((world.x - world.y) * _iso_w(), (world.x + world.y) * _iso_h())


func get_camera_world() -> Vector2:
	return camera_world


func get_camera_screen_offset() -> Vector2:
	if isometric:
		return _project_iso(camera_world)
	return camera_world * _ortho_tile_px()


func get_camera_zoom() -> float:
	return camera_zoom


func _iso_cell_center(x: int, y: int) -> Vector2:
	return _project_iso(Vector2(float(x), float(y)))


func _iso_offset() -> Vector2:
	## Center the diamond map in the control.
	var use_sz: Vector2 = size
	if use_sz.x < 4.0 or use_sz.y < 4.0:
		use_sz = custom_minimum_size
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for y in range(farm.height):
		for x in range(farm.width):
			var c: Vector2 = _iso_cell_center(x, y)
			for p in _cell_corners_vec(c):
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)
	var map_c: Vector2 = Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	return use_sz * 0.5 - map_c - get_camera_screen_offset()


func _cell_corners_vec(center: Vector2) -> Array[Vector2]:
	var cx: float = center.x
	var cy: float = center.y
	return [
		Vector2(cx, cy - _iso_h()),
		Vector2(cx + _iso_w(), cy),
		Vector2(cx, cy + _iso_h()),
		Vector2(cx - _iso_w(), cy),
	]


func _draw() -> void:
	if farm == null:
		return
	if isometric:
		_draw_iso()
	else:
		_draw_ortho()


func _draw_ortho() -> void:
	var tile_px: float = _ortho_tile_px()
	var o: Vector2 = Vector2(
		float(COMPASS_MARGIN),
		float(COMPASS_MARGIN + (10 if show_compass_labels else 0))
	)
	var gw: float = float(farm.width) * tile_px
	var gh: float = float(farm.height) * tile_px

	if show_compass_labels:
		var fnt: Font = get_theme_default_font()
		if fnt == null:
			fnt = ThemeDB.fallback_font
		var fs: int = 14
		var lab: Color = Color(0.96, 0.96, 0.94, 0.95)
		draw_string(fnt, Vector2(o.x + gw * 0.5 - 5.0, o.y - 4.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lab)
		draw_string(fnt, Vector2(o.x + gw * 0.5 - 5.0, o.y + gh + 16.0), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lab)
		draw_string(fnt, Vector2(o.x - 16.0, o.y + gh * 0.5 - 6.0), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lab)
		draw_string(fnt, Vector2(o.x + gw + 6.0, o.y + gh * 0.5 - 6.0), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lab)

	for y in range(farm.height):
		for x in range(farm.width):
			var p := Vector2i(x, y)
			var world_pos := Vector2(float(x), float(y)) - camera_world
			var r := Rect2(
				o.x + world_pos.x * tile_px + 1.0,
				o.y + world_pos.y * tile_px + 1.0,
				tile_px - 2.0,
				tile_px - 2.0
			)
			var gnd: String = farm.get_ground_at(p)
			var fill: Color = COL_GRASS if gnd == "grass" else COL_SOIL
			draw_rect(r, fill)
			draw_rect(r, OUTLINE, false, 2.0)
			_draw_crop_ortho(p, r)

	var dr := Rect2(
		o.x + (float(drone_grid.x) - camera_world.x) * tile_px + 6.0,
		o.y + (float(drone_grid.y) - camera_world.y) * tile_px + 6.0,
		tile_px - 12.0,
		tile_px - 12.0
	)
	draw_rect(dr, COL_DRONE, true)
	draw_rect(dr, Color.WHITE, false, 2.0)


func _draw_crop_ortho(p: Vector2i, r: Rect2) -> void:
	var tile_px: float = _ortho_tile_px()
	var c: String = farm.get_crop_at(p)
	if c == FarmState.HAY_ID:
		var pr: float = farm.get_hay_progress_at(p)
		var rad: float = tile_px * lerpf(0.18, 0.32, pr)
		var col: Color = COL_HAY_GROW.lerp(COL_HAY_READY, pr)
		draw_circle(r.get_center(), rad, col)
	elif c == "wheat":
		draw_circle(r.get_center(), tile_px * 0.28, COL_WHEAT)
	elif c == "carrot":
		draw_circle(r.get_center(), tile_px * 0.22, Color(0.95, 0.5, 0.15))


func _draw_iso() -> void:
	var off: Vector2 = _iso_offset()
	var order: Array[Vector2i] = []
	for diag in range(farm.width + farm.height - 1):
		for x in range(farm.width):
			var y: int = diag - x
			if y >= 0 and y < farm.height:
				order.append(Vector2i(x, y))

	for p in order:
		var center: Vector2 = _iso_cell_center(p.x, p.y) + off
		var gnd: String = farm.get_ground_at(p)
		var poly: PackedVector2Array = PackedVector2Array(_cell_corners_vec(center))
		var fill: Color = COL_GRASS if gnd == "grass" else COL_SOIL
		var left_col: Color = COL_GRASS_SIDE_L if gnd == "grass" else COL_SOIL_SIDE_L
		var right_col: Color = COL_GRASS_SIDE_R if gnd == "grass" else COL_SOIL_SIDE_R
		var side_drop: Vector2 = Vector2(0.0, _cube_h())
		var left_face := PackedVector2Array([poly[3], poly[2], poly[2] + side_drop, poly[3] + side_drop])
		var right_face := PackedVector2Array([poly[1], poly[2], poly[2] + side_drop, poly[1] + side_drop])
		draw_colored_polygon(left_face, left_col)
		draw_colored_polygon(right_face, right_col)
		draw_colored_polygon(poly, fill)
		## Top-face outline and slight directional shading.
		var dark: Color = COL_GRASS_DARK if gnd == "grass" else COL_SOIL_DARK
		var e1: Vector2 = poly[3]
		var e2: Vector2 = poly[0]
		var e3: Vector2 = poly[1]
		draw_line(e1, e2, dark, 2.0)
		draw_line(e2, e3, OUTLINE, 1.5)
		draw_line(poly[1], poly[2], OUTLINE, 1.5)
		draw_line(poly[2], poly[3], OUTLINE, 1.5)
		draw_line(poly[3], poly[0], OUTLINE, 1.5)
		draw_line(poly[2], poly[2] + side_drop, OUTLINE, 1.2)
		draw_line(poly[3], poly[3] + side_drop, OUTLINE, 1.2)
		draw_line(poly[1], poly[1] + side_drop, OUTLINE, 1.2)
		draw_line(poly[3] + side_drop, poly[2] + side_drop, OUTLINE, 1.2)
		draw_line(poly[1] + side_drop, poly[2] + side_drop, OUTLINE, 1.2)
		_draw_crop_iso(p, center)

	var dc: Vector2 = _iso_cell_center(drone_grid.x, drone_grid.y) + off
	_draw_drone_iso(dc)


func _draw_crop_iso(p: Vector2i, cell_center: Vector2) -> void:
	var c: String = farm.get_crop_at(p)
	var top: Vector2 = cell_center + Vector2(0.0, -_iso_h() * 0.35)
	if c == FarmState.HAY_ID:
		var pr: float = farm.get_hay_progress_at(p)
		var rh: float = lerpf(6.0, 14.0, pr) * (_iso_h() / 16.0)
		var rw: float = lerpf(5.0, 9.0, pr) * (_iso_w() / 28.0)
		var col: Color = COL_HAY_GROW.lerp(COL_HAY_READY, pr)
		draw_colored_polygon(_stalk_polygon(top, rw, rh * 1.4), col)
	elif c == "wheat":
		draw_colored_polygon(_stalk_polygon(top, 7.0 * (_iso_w() / 28.0), 18.0 * (_iso_h() / 16.0)), COL_WHEAT)
	elif c == "carrot":
		draw_colored_polygon(_stalk_polygon(top, 6.0 * (_iso_w() / 28.0), 10.0 * (_iso_h() / 16.0)), Color(0.95, 0.5, 0.15))


func _stalk_polygon(base: Vector2, half_w: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([
		base + Vector2(-half_w, 0.0),
		base + Vector2(half_w, 0.0),
		base + Vector2(0.0, -height),
	])


func _draw_drone_iso(center: Vector2) -> void:
	var body_r: float = minf(_iso_w(), _iso_h()) * 0.55
	var feet_y: float = _iso_h() * 0.38
	var cpos: Vector2 = center + Vector2(0.0, -body_r * 0.45)
	draw_circle(cpos, body_r, COL_DRONE)
	draw_arc(cpos, body_r - 0.5, 0.0, TAU, 28, Color.WHITE, 2.0, true)
	var spread: float = body_r * 0.45
	var outs: Array[Vector2] = [
		Vector2(-1.0, -0.35), Vector2(1.0, -0.35), Vector2(-1.0, 0.2), Vector2(1.0, 0.2),
	]
	for o in outs:
		var a: Vector2 = center + Vector2(o.x * spread, o.y * body_r * 0.2)
		var b: Vector2 = a + Vector2(o.x * body_r * 0.35, feet_y)
		draw_line(a, b, Color(0.14, 0.11, 0.09), 2.5)
