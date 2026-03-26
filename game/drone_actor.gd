extends RefCounted
class_name DroneActor

## Grid-aligned drone. Moves wrap on all edges (torus).

signal moved(grid_pos: Vector2i)

var farm: FarmState
var grid_pos: Vector2i = Vector2i.ZERO


func bind(p_farm: FarmState, start: Vector2i) -> void:
	farm = p_farm
	grid_pos = start


func snap_to_start() -> void:
	if farm == null:
		return
	grid_pos = farm.drone_start_pos()
	moved.emit(grid_pos)


func move_dir(direction: String) -> bool:
	if farm == null:
		return false
	var d := grid_pos
	match direction:
		"north":
			d.y -= 1
			if d.y < 0:
				d.y = farm.height - 1
		"south":
			d.y += 1
			if d.y >= farm.height:
				d.y = 0
		"east":
			d.x += 1
			if d.x >= farm.width:
				d.x = 0
		"west":
			d.x -= 1
			if d.x < 0:
				d.x = farm.width - 1
		_:
			return false
	grid_pos = d
	moved.emit(grid_pos)
	return true
