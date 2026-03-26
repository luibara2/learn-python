extends CharacterBody2D

var tile_size = 128
var grid_pos = Vector2(0, 0)  # starts at tile 0,0

func _ready():
	position = grid_pos * tile_size + Vector2(0, 0)

func move(direction):
	match direction:
		"north": grid_pos.y -= 1
		"south": grid_pos.y += 1
		"east":  grid_pos.x += 1
		"west":  grid_pos.x -= 1
	position = grid_pos * tile_size + Vector2(0, 0)

func _input(event):
	if event.is_action_pressed("ui_up"):    move("north")
	if event.is_action_pressed("ui_down"):  move("south")
	if event.is_action_pressed("ui_right"): move("east")
	if event.is_action_pressed("ui_left"):  move("west")
