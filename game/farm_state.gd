extends RefCounted
class_name FarmState

## Hay on grass ripens over real time (see HAY_GROW_SEC).

const HAY_ID := "hay"
## Seconds from regrowth start until hay can be harvested.
const HAY_GROW_SEC := 2.0

var width: int
var height: int
## "grass" | "soil"
var ground: PackedStringArray = PackedStringArray()
## "" | "hay" | "wheat" | "carrot" | ...
var crops: PackedStringArray = PackedStringArray()
## Hay on grass only: 0..1 while growing, >= 1 when ready to harvest.
var hay_progress: PackedFloat32Array = PackedFloat32Array()


func _init(w: int, h: int) -> void:
	width = w
	height = h
	ground.resize(w * h)
	crops.resize(w * h)
	hay_progress.resize(w * h)
	reset_to_default()


## Bottom-left in grid coords (y down): x=0, y=height-1
func drone_start_pos() -> Vector2i:
	return Vector2i(0, height - 1)


func reset_to_default() -> void:
	for i in range(width * height):
		ground[i] = "grass"
		crops[i] = HAY_ID
		hay_progress[i] = 0.0


func _idx(x: int, y: int) -> int:
	return y * width + x


func in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.y >= 0 and grid_pos.x < width and grid_pos.y < height


func get_ground_at(grid_pos: Vector2i) -> String:
	if not in_bounds(grid_pos):
		return ""
	return ground[_idx(grid_pos.x, grid_pos.y)]


func get_crop_at(grid_pos: Vector2i) -> String:
	if not in_bounds(grid_pos):
		return ""
	return crops[_idx(grid_pos.x, grid_pos.y)]


## 0..1 for hay on grass; otherwise 0.
func get_hay_progress_at(grid_pos: Vector2i) -> float:
	if not in_bounds(grid_pos):
		return 0.0
	var i := _idx(grid_pos.x, grid_pos.y)
	if crops[i] != HAY_ID or ground[i] != "grass":
		return 0.0
	return hay_progress[i]


func _hay_ready(i: int) -> bool:
	return hay_progress[i] >= 1.0


func is_hay_ready_at(grid_pos: Vector2i) -> bool:
	if not in_bounds(grid_pos):
		return false
	var i := _idx(grid_pos.x, grid_pos.y)
	return crops[i] == HAY_ID and ground[i] == "grass" and _hay_ready(i)


func can_harvest_at(grid_pos: Vector2i) -> bool:
	if not in_bounds(grid_pos):
		return false
	var i := _idx(grid_pos.x, grid_pos.y)
	var c: String = crops[i]
	if c == "":
		return false
	if c == HAY_ID:
		return ground[i] == "grass" and _hay_ready(i)
	return true


## Call every frame from the game loop so hay grows without drone moves.
func process_growth(delta: float) -> void:
	if delta <= 0.0:
		return
	var step: float = delta / HAY_GROW_SEC
	for i in range(width * height):
		if ground[i] != "grass":
			continue
		if crops[i] != HAY_ID:
			continue
		if hay_progress[i] < 1.0:
			hay_progress[i] = minf(1.0, hay_progress[i] + step)


func till_at(grid_pos: Vector2i) -> void:
	if not in_bounds(grid_pos):
		return
	var i := _idx(grid_pos.x, grid_pos.y)
	ground[i] = "soil"
	crops[i] = ""
	hay_progress[i] = 0.0


func plant_at(grid_pos: Vector2i, entity: String) -> bool:
	if not in_bounds(grid_pos):
		return false
	var i := _idx(grid_pos.x, grid_pos.y)
	if ground[i] != "soil":
		return false
	if crops[i] != "":
		return false
	crops[i] = entity
	hay_progress[i] = 0.0
	return true


func harvest_at(grid_pos: Vector2i) -> String:
	if not in_bounds(grid_pos):
		return ""
	var i := _idx(grid_pos.x, grid_pos.y)
	var c: String = crops[i]
	if c == "":
		return ""
	if c == HAY_ID:
		if ground[i] != "grass":
			return ""
		if not _hay_ready(i):
			return ""
		hay_progress[i] = 0.0
		return HAY_ID
	crops[i] = ""
	hay_progress[i] = 0.0
	return c


func to_save_dict() -> Dictionary:
	var g: Array = []
	var c: Array = []
	var h: Array = []
	for i in range(width * height):
		g.append(ground[i])
		c.append(crops[i])
		h.append(hay_progress[i])
	return {"w": width, "h": height, "ground": g, "crops": c, "hay_progress": h}


func apply_save_dict(d: Dictionary) -> bool:
	var w2: int = int(d.get("w", 0))
	var h2: int = int(d.get("h", 0))
	if w2 != width or h2 != height:
		return false
	var g: Variant = d.get("ground")
	var c: Variant = d.get("crops")
	var hp: Variant = d.get("hay_progress")
	if not g is Array or not c is Array or not hp is Array:
		return false
	if (g as Array).size() != width * height:
		return false
	var ga: Array = g
	var ca: Array = c
	var ha: Array = hp
	for i in range(width * height):
		ground[i] = str(ga[i])
		crops[i] = str(ca[i])
		hay_progress[i] = float(ha[i])
	return true
