extends Control
class_name FarmView

@export var tile_size: int = 56
@export var grid_width: int = 8
@export var grid_height: int = 8

var farm: FarmState
var drone_grid: Vector2i = Vector2i.ZERO

const COL_GRASS := Color(0.35, 0.62, 0.32)
const COL_SOIL := Color(0.45, 0.32, 0.22)
const COL_WHEAT := Color(0.85, 0.75, 0.35)
const COL_HAY_GROW := Color(0.55, 0.72, 0.38)
const COL_HAY_READY := Color(0.82, 0.7, 0.28)
const COL_DRONE := Color(0.92, 0.45, 0.2)


func setup(p_farm: FarmState, start: Vector2i) -> void:
	farm = p_farm
	drone_grid = start
	custom_minimum_size = Vector2(farm.width * tile_size, farm.height * tile_size)
	queue_redraw()


func set_drone_cell(g: Vector2i) -> void:
	drone_grid = g
	queue_redraw()


func _draw() -> void:
	if farm == null:
		return
	var outline := Color(0.12, 0.1, 0.09)
	for y in range(farm.height):
		for x in range(farm.width):
			var p := Vector2i(x, y)
			var r := Rect2(x * tile_size + 1, y * tile_size + 1, tile_size - 2, tile_size - 2)
			var gnd: String = farm.get_ground_at(p)
			var fill: Color = COL_GRASS if gnd == "grass" else COL_SOIL
			draw_rect(r, fill)
			draw_rect(r, outline, false, 2.0)
			var c: String = farm.get_crop_at(p)
			if c == FarmState.HAY_ID:
				var pr: float = farm.get_hay_progress_at(p)
				var ready: bool = pr >= 1.0
				var rad: float = tile_size * lerpf(0.18, 0.32, pr)
				var col: Color = COL_HAY_GROW.lerp(COL_HAY_READY, pr)
				draw_circle(r.get_center(), rad, col)
			elif c == "wheat":
				draw_circle(r.get_center(), tile_size * 0.28, COL_WHEAT)
			elif c == "carrot":
				draw_circle(r.get_center(), tile_size * 0.22, Color(0.95, 0.5, 0.15))

	var dr := Rect2(
		drone_grid.x * tile_size + 6,
		drone_grid.y * tile_size + 6,
		tile_size - 12,
		tile_size - 12
	)
	draw_rect(dr, COL_DRONE, true)
	draw_rect(dr, Color.WHITE, false, 2.0)
