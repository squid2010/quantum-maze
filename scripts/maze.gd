extends Node2D
class_name MazeGenerator

@export var maze_size: Vector2i = Vector2i(21, 21)
@export var cell_size: int = 32

# Colors
@export var wall_color: Color = Color.BLACK
@export var path_color: Color = Color.WHITE
@export var switch_color: Color = Color.YELLOW
@export var door_color: Color = Color.RED
@export var plate_color: Color = Color.BLUE
@export var gate_color: Color = Color.PURPLE

# Core data
var grid: Array[Array] = []
var switches: Dictionary = {}  # Vector2i -> bool (active state)
var doors: Dictionary = {}     # Vector2i -> bool (open state)  
var plates: Dictionary = {}    # Vector2i -> bool (pressed state)
var gates: Dictionary = {}     # Vector2i -> bool (open state)

# Puzzle connections
var switch_doors: Dictionary = {}  # switch_pos -> door_pos
var plate_gates: Dictionary = {}   # plate_pos -> gate_pos

# Collision bodies
var wall_bodies: Array[StaticBody2D] = []
var door_bodies: Dictionary = {}   # door_pos -> StaticBody2D
var gate_bodies: Dictionary = {}   # gate_pos -> StaticBody2D

signal element_toggled

func _ready():
	generate()

func generate():
	_clear_collision_bodies()
	_init_grid()
	_generate_maze()
	_add_puzzles()
	_create_collision_bodies()
	queue_redraw()

func _clear_collision_bodies():
	for body in wall_bodies:
		if is_instance_valid(body):
			body.queue_free()
	wall_bodies.clear()
	
	for pos in door_bodies:
		if is_instance_valid(door_bodies[pos]):
			door_bodies[pos].queue_free()
	door_bodies.clear()
	
	for pos in gate_bodies:
		if is_instance_valid(gate_bodies[pos]):
			gate_bodies[pos].queue_free()
	gate_bodies.clear()

func _init_grid():
	grid.clear()
	switches.clear()
	doors.clear()
	plates.clear()
	gates.clear()
	switch_doors.clear()
	plate_gates.clear()
	
	# Fill with walls
	for y in maze_size.y:
		grid.append([])
		for x in maze_size.x:
			grid[y].append(true)  # true = wall

func _generate_maze():
	var visited: Array[Array] = []
	for y in maze_size.y:
		visited.append([])
		for x in maze_size.x:
			visited[y].append(false)
	
	var stack: Array[Vector2i] = []
	var current = Vector2i(1, 1)
	grid[1][1] = false  # Starting path
	visited[1][1] = true
	
	while true:
		var neighbors = _get_unvisited_neighbors(current, visited)
		
		if neighbors.size() > 0:
			var next = neighbors[randi() % neighbors.size()]
			var wall = (current + next) / 2
			
			grid[wall.y][wall.x] = false
			grid[next.y][next.x] = false
			visited[next.y][next.x] = true
			
			stack.push_back(current)
			current = next
		else:
			if stack.is_empty():
				break
			current = stack.pop_back()
	
	# Add entrance/exit
	grid[0][1] = false
	grid[maze_size.y - 1][maze_size.x - 2] = false

func _get_unvisited_neighbors(pos: Vector2i, visited: Array[Array]) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var dirs = [Vector2i(0, -2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0)]
	
	for dir in dirs:
		var neighbor = pos + dir
		if _is_valid_pos(neighbor) and not visited[neighbor.y][neighbor.x]:
			neighbors.append(neighbor)
	
	return neighbors

func _is_valid_pos(pos: Vector2i) -> bool:
	return pos.x > 0 and pos.x < maze_size.x - 1 and pos.y > 0 and pos.y < maze_size.y - 1

func _add_puzzles():
	var paths = _get_path_cells()
	if paths.size() < 8:
		return
	
	# Simple switch-door pair
	var switch_pos = paths[randi() % (paths.size() / 3)]
	var door_pos = paths[paths.size() - 1 - randi() % (paths.size() / 3)]
	_add_switch_door_pair(switch_pos, door_pos)
	
	# Pressure plate-gate pair
	var plate_pos = paths[randi() % (paths.size() / 2)]
	var gate_pos = paths[paths.size() / 2 + randi() % (paths.size() / 3)]
	_add_plate_gate_pair(plate_pos, gate_pos)

func _get_path_cells() -> Array[Vector2i]:
	var paths: Array[Vector2i] = []
	for y in maze_size.y:
		for x in maze_size.x:
			if not grid[y][x]:  # is path
				paths.append(Vector2i(x, y))
	return paths

func _add_switch_door_pair(switch_pos: Vector2i, door_pos: Vector2i):
	switches[switch_pos] = false
	doors[door_pos] = false
	switch_doors[switch_pos] = door_pos

func _add_plate_gate_pair(plate_pos: Vector2i, gate_pos: Vector2i):
	plates[plate_pos] = false
	gates[gate_pos] = false
	plate_gates[plate_pos] = gate_pos

func _create_collision_bodies():
	# Create wall collision bodies
	for y in maze_size.y:
		for x in maze_size.x:
			if grid[y][x]:  # is wall
				_create_wall_collision(Vector2i(x, y))
	
	# Create door collision bodies (initially closed)
	for pos in doors:
		_create_door_collision(pos)
	
	# Create gate collision bodies (initially closed)  
	for pos in gates:
		_create_gate_collision(pos)

func _create_wall_collision(pos: Vector2i):
	var body = StaticBody2D.new()
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	
	rect.size = Vector2(cell_size, cell_size)
	shape.shape = rect
	shape.position = Vector2(cell_size / 2, cell_size / 2)
	
	body.add_child(shape)
	body.position = Vector2(pos.x * cell_size, pos.y * cell_size)
	add_child(body)
	wall_bodies.append(body)

func _create_door_collision(pos: Vector2i):
	var body = StaticBody2D.new()
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	
	rect.size = Vector2(cell_size, cell_size)
	shape.shape = rect
	shape.position = Vector2(cell_size / 2, cell_size / 2)
	
	body.add_child(shape)
	body.position = Vector2(pos.x * cell_size, pos.y * cell_size)
	add_child(body)
	door_bodies[pos] = body

func _create_gate_collision(pos: Vector2i):
	var body = StaticBody2D.new()
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	
	rect.size = Vector2(cell_size, cell_size)
	shape.shape = rect
	shape.position = Vector2(cell_size / 2, cell_size / 2)
	
	body.add_child(shape)
	body.position = Vector2(pos.x * cell_size, pos.y * cell_size)
	add_child(body)
	gate_bodies[pos] = body

# Public interface
func is_wall_at(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= maze_size.x or pos.y < 0 or pos.y >= maze_size.y:
		return true
	return grid[pos.y][pos.x]

func is_path_at(pos: Vector2i) -> bool:
	if is_wall_at(pos):
		return false
	# Check for closed doors/gates
	if doors.has(pos) and not doors[pos]:
		return false
	if gates.has(pos) and not gates[pos]:
		return false
	return true

func toggle_switch(pos: Vector2i) -> bool:
	if switches.has(pos):
		switches[pos] = not switches[pos]
		_update_doors()
		element_toggled.emit()
		queue_redraw()
		return switches[pos]
	return false

func activate_pressure_plate(pos: Vector2i):
	if plates.has(pos):
		plates[pos] = true
		_update_gates()
		element_toggled.emit()
		queue_redraw()

func deactivate_pressure_plate(pos: Vector2i):
	if plates.has(pos):
		plates[pos] = false
		_update_gates()
		element_toggled.emit()
		queue_redraw()

func _update_doors():
	for switch_pos in switch_doors:
		var door_pos = switch_doors[switch_pos]
		var door_open = switches[switch_pos]
		doors[door_pos] = door_open
		
		# Update collision body visibility
		if door_bodies.has(door_pos):
			door_bodies[door_pos].set_collision_layer_value(1, not door_open)
			door_bodies[door_pos].set_collision_mask_value(1, not door_open)

func _update_gates():
	for plate_pos in plate_gates:
		var gate_pos = plate_gates[plate_pos]
		var gate_open = plates[plate_pos]
		gates[gate_pos] = gate_open
		
		# Update collision body visibility
		if gate_bodies.has(gate_pos):
			gate_bodies[gate_pos].set_collision_layer_value(1, not gate_open)
			gate_bodies[gate_pos].set_collision_mask_value(1, not gate_open)

func has_switch_at(pos: Vector2i) -> bool:
	return switches.has(pos)

func has_pressure_plate_at(pos: Vector2i) -> bool:
	return plates.has(pos)

func _draw():
	# Draw basic maze
	for y in maze_size.y:
		for x in maze_size.x:
			var rect = Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			var color = wall_color if grid[y][x] else path_color
			draw_rect(rect, color)
	
	# Draw interactive elements
	_draw_switches()
	_draw_doors()
	_draw_pressure_plates()
	_draw_gates()

func _draw_switches():
	for pos in switches:
		var rect = Rect2(pos.x * cell_size + 8, pos.y * cell_size + 8, 16, 16)
		var color = Color.GREEN if switches[pos] else switch_color
		draw_rect(rect, color)

func _draw_doors():
	for pos in doors:
		if not doors[pos]:  # Only draw if closed
			var rect = Rect2(pos.x * cell_size, pos.y * cell_size, cell_size, cell_size)
			draw_rect(rect, door_color)

func _draw_pressure_plates():
	for pos in plates:
		var rect = Rect2(pos.x * cell_size + 4, pos.y * cell_size + 4, 24, 24)
		var color = Color.LIGHT_BLUE if plates[pos] else plate_color
		draw_rect(rect, color)

func _draw_gates():
	for pos in gates:
		if not gates[pos]:  # Only draw if closed
			var rect = Rect2(pos.x * cell_size, pos.y * cell_size, cell_size, cell_size)
			draw_rect(rect, gate_color)
