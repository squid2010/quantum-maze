extends Node2D
class_name MazeGenerator

# --- Goal Scene ---
const GoalScene = preload("res://scenes/Goal.tscn")
var goal_instance = null
# ------------------

# --- Level Progression ---
@export var maze_sizes: Array[Vector2i] = [
	Vector2i(15, 11),
	Vector2i(19, 15),
	Vector2i(23, 19),
	Vector2i(27, 21)
]
var current_level_index: int = 0
# -------------------------

@export var cell_size: int = 32
@export var num_temporal_puzzles: int = 1 
@export var add_side_puzzles: bool = true

# Colors
@export var wall_color: Color = Color.BLACK
@export var path_color: Color = Color.WHITE
@export var switch_color: Color = Color.YELLOW
@export var reset_switch_color: Color = Color.CYAN # New color for reset switches
@export var door_color: Color = Color.RED
@export var multi_switch_door_color: Color = Color.ORANGE
@export var plate_color: Color = Color.BLUE
@export var gate_color: Color = Color.PURPLE

# Core data
var grid: Array[Array] = []
var switches: Dictionary = {}
var reset_switches: Array[Vector2i] = [] # New data for reset switches
var doors: Dictionary = {}
var plates: Dictionary = {}
var gates: Dictionary = {}

# Puzzle connections
var door_switches: Dictionary = {}
var plate_gates: Dictionary = {}

# Collision bodies
var wall_bodies: Array[StaticBody2D] = []
var door_bodies: Dictionary = {}
var gate_bodies: Dictionary = {}

# Signal
signal level_generated

# --- A* Pathfinding Data Structure ---
class AStarPoint:
	var pos: Vector2i
	var g_score: float = INF
	var h_score: float = INF
	var f_score: float = INF
	var parent = null
	func _init(_pos: Vector2i): pos = _pos
# ------------------------------------

func _ready():
	generate()

func next_level():
	print("Level complete! Generating next level...")
	current_level_index = (current_level_index + 1) % maze_sizes.size()
	generate()

func generate():
	# Randomize obstacles based on level size
	if current_level_index < 2:
		num_temporal_puzzles = randi_range(1, 2)
	else:
		num_temporal_puzzles = randi_range(2, 4)
	print("Generating level %d with %d temporal puzzles." % [current_level_index + 1, num_temporal_puzzles])

	_clear_level_objects()
	_init_grid()
	_generate_maze()
	
	var puzzles_added = _add_temporal_puzzles()
	if puzzles_added < num_temporal_puzzles:
		print("WARNING: Could not add all requested puzzles. Retrying generation...")
		generate()
		return
			
	if add_side_puzzles:
		_add_side_puzzles()
	
	_create_collision_bodies()
	_create_goal()
	queue_redraw()
	level_generated.emit()

func _create_goal():
	var exit_pos = Vector2i(get_maze_size().x - 2, get_maze_size().y - 1)
	
	goal_instance = GoalScene.instantiate()
	goal_instance.position = Vector2(exit_pos.x * cell_size, exit_pos.y * cell_size)
	goal_instance.body_entered.connect(_on_goal_entered)
	add_child(goal_instance)

func get_maze_size() -> Vector2i:
	return maze_sizes[current_level_index]

func get_current_level_index() -> int:
	return current_level_index

func _clear_level_objects():
	for body in wall_bodies:
		if is_instance_valid(body): body.queue_free()
	wall_bodies.clear()
	for pos in door_bodies:
		if is_instance_valid(door_bodies[pos]): door_bodies[pos].queue_free()
	door_bodies.clear()
	for pos in gate_bodies:
		if is_instance_valid(gate_bodies[pos]): gate_bodies[pos].queue_free()
	gate_bodies.clear()
	
	if is_instance_valid(goal_instance):
		goal_instance.queue_free()
		goal_instance = null

func _init_grid():
	var current_maze_size = get_maze_size()
	grid.clear()
	switches.clear()
	reset_switches.clear()
	doors.clear()
	plates.clear()
	gates.clear()
	door_switches.clear()
	plate_gates.clear()
	for y in current_maze_size.y:
		grid.append([])
		for x in current_maze_size.x:
			grid[y].append(true)

func _generate_maze():
	var current_maze_size = get_maze_size()
	var visited: Array[Array] = []
	for y in current_maze_size.y:
		visited.append([])
		for x in current_maze_size.x: visited[y].append(false)
	
	var stack: Array[Vector2i] = []
	var current = Vector2i(1, 1)
	grid[1][1] = false
	visited[1][1] = true
	
	while true:
		var neighbors = _get_unvisited_neighbors(current, visited)
		if not neighbors.is_empty():
			var next = neighbors.pick_random()
			var wall = (current + next) / 2
			grid[wall.y][wall.x] = false
			grid[next.y][next.x] = false
			visited[next.y][next.x] = true
			stack.push_back(current)
			current = next
		elif not stack.is_empty():
			current = stack.pop_back()
		else:
			break
	grid[0][1] = false
	grid[current_maze_size.y - 1][current_maze_size.x - 2] = false

func _get_unvisited_neighbors(pos: Vector2i, visited: Array[Array]) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var dirs = [Vector2i(0, -2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0)]
	for dir in dirs:
		var neighbor = pos + dir
		if _is_valid_pos(neighbor) and not visited[neighbor.y][neighbor.x]:
			neighbors.append(neighbor)
	return neighbors

func _is_valid_pos(pos: Vector2i) -> bool:
	var current_maze_size = get_maze_size()
	return pos.x > 0 and pos.x < current_maze_size.x - 1 and pos.y > 0 and pos.y < current_maze_size.y - 1

func _add_temporal_puzzles() -> int:
	var current_maze_size = get_maze_size()
	var puzzles_added = 0
	var current_start_pos = Vector2i(1, 1)
	var end_pos = Vector2i(current_maze_size.x - 2, current_maze_size.y - 1)
	
	for i in range(num_temporal_puzzles):
		var main_path = _find_astar_path(current_start_pos, end_pos)
		
		if main_path.is_empty() or main_path.size() < 4:
			print("Path for puzzle #%d is too short or non-existent. Stopping puzzle placement." % (i + 1))
			break

		var plate_index = main_path.size() / 3
		var gate_index = main_path.size() * 2 / 3

		var plate_pos = main_path[plate_index]
		var gate_pos = main_path[gate_index]

		if plate_pos == current_start_pos or gate_pos == end_pos or plate_pos == gate_pos:
			print("Failed to find distinct positions for puzzle #%d." % (i + 1))
			break

		_add_plate_gate_pair(plate_pos, gate_pos)
		
		# Now, the A* check for solvability considers the gate as an openable obstacle
		var path_after_gate = _find_astar_path(gate_pos, end_pos)
		if path_after_gate.is_empty():
			print("Puzzle #%d is unsolvable. Removing it and stopping." % (i + 1))
			plates.erase(plate_pos)
			gates.erase(gate_pos)
			plate_gates.erase(plate_pos)
			break

		puzzles_added += 1
		current_start_pos = gate_pos
		print("Successfully created temporal puzzle #%d. Plate: %s, Gate: %s" % [puzzles_added, plate_pos, gate_pos])

	return puzzles_added

func _add_side_puzzles():
	var dead_ends = _find_dead_ends()
	var path_cells = _get_path_cells()
	path_cells.shuffle()
	
	var puzzles_to_add = min(dead_ends.size(), randi_range(2, 5))
	var used_cells: Array[Vector2i] = []

	for i in range(puzzles_to_add):
		if dead_ends.is_empty() or path_cells.is_empty():
			break
			
		var puzzle_pos = dead_ends.pop_front()
		used_cells.append(puzzle_pos)

		# Decide what kind of puzzle to create
		var puzzle_type = randi_range(0, 10)
		
		if puzzle_type > 8 and current_level_index > 0: # 20% chance for a Reset Switch
			reset_switches.append(puzzle_pos)
			print("Added Reset Switch at %s" % puzzle_pos)
		else: # 80% chance for a Door puzzle
			var num_switches = 1
			if current_level_index >= 2 and randf() < 0.6: num_switches = 2
			elif current_level_index >= 1 and randf() < 0.4: num_switches = 2

			var switch_positions: Array[Vector2i] = []
			var found_all_switches = true
			for j in range(num_switches):
				var found_switch_pos = false
				var best_pos = Vector2i.ZERO
				for cell in path_cells:
					if not used_cells.has(cell) and cell.distance_to(puzzle_pos) > 4:
						best_pos = cell
						found_switch_pos = true
						break
				if found_switch_pos:
					switch_positions.append(best_pos)
					used_cells.append(best_pos)
					path_cells.erase(best_pos)
				else:
					found_all_switches = false
					break
			
			if found_all_switches:
				_add_door_and_switches(puzzle_pos, switch_positions)
				print("Added %d-switch puzzle. Door: %s, Switches: %s" % [num_switches, puzzle_pos, switch_positions])

func _find_dead_ends() -> Array[Vector2i]:
	var dead_ends: Array[Vector2i] = []
	var path_cells = _get_path_cells()
	var current_maze_size = get_maze_size()
	
	for pos in path_cells:
		var open_neighbors = 0
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not grid[pos.y + dir.y][pos.x + dir.x]:
				open_neighbors += 1
		if open_neighbors == 1:
			if pos != Vector2i(1,0) and pos != Vector2i(current_maze_size.x-2, current_maze_size.y-1):
				dead_ends.append(pos)
	return dead_ends

func _get_path_cells() -> Array[Vector2i]:
	var paths: Array[Vector2i] = []
	var current_maze_size = get_maze_size()
	for y in range(1, current_maze_size.y - 1):
		for x in range(1, current_maze_size.x - 1):
			if not grid[y][x]: paths.append(Vector2i(x, y))
	return paths

func _add_door_and_switches(door_pos: Vector2i, switch_positions: Array[Vector2i]):
	doors[door_pos] = false
	door_switches[door_pos] = switch_positions
	for switch_pos in switch_positions:
		switches[switch_pos] = false

func _add_plate_gate_pair(plate_pos: Vector2i, gate_pos: Vector2i):
	plates[plate_pos] = false
	gates[gate_pos] = false
	plate_gates[plate_pos] = gate_pos

func _create_collision_bodies():
	var current_maze_size = get_maze_size()
	for y in current_maze_size.y:
		for x in current_maze_size.x:
			if grid[y][x]: _create_wall_collision(Vector2i(x, y))
	for pos in doors: _create_door_collision(pos)
	for pos in gates: _create_gate_collision(pos)

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
	body.name = "DoorBody_%s" % pos
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
	body.name = "GateBody_%s" % pos
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(cell_size, cell_size)
	shape.shape = rect
	shape.position = Vector2(cell_size / 2, cell_size / 2)
	body.add_child(shape)
	body.position = Vector2(pos.x * cell_size, pos.y * cell_size)
	add_child(body)
	gate_bodies[pos] = body

func is_path_at(pos: Vector2i, for_astar: bool = false) -> bool:
	if is_wall_at(pos): return false
	
	# For A*, assume we can solve puzzles
	if for_astar:
		# A* assumes we can always find a way to open a door or gate
		if doors.has(pos) or gates.has(pos):
			return true
	
	# For player/echo collision, check current state
	if doors.has(pos) and not doors[pos]: return false
	if gates.has(pos) and not gates[pos]: return false
	return true

func is_wall_at(pos: Vector2i) -> bool:
	var current_maze_size = get_maze_size()
	if pos.x < 0 or pos.x >= current_maze_size.x or pos.y < 0 or pos.y >= current_maze_size.y:
		return true
	return grid[pos.y][pos.x]

func toggle_switch(pos: Vector2i):
	if reset_switches.has(pos):
		# Deactivate all other switches
		for switch_pos in switches:
			switches[switch_pos] = false
		print("Reset switch activated!")
	elif switches.has(pos):
		switches[pos] = not switches[pos]
	
	_update_doors()
	queue_redraw()

func activate_pressure_plate(pos: Vector2i):
	if plates.has(pos):
		plates[pos] = true
		_update_gates()
		queue_redraw()

func deactivate_pressure_plate(pos: Vector2i):
	if plates.has(pos):
		plates[pos] = false
		_update_gates()
		queue_redraw()

func _update_doors():
	for door_pos in door_switches:
		var required_switches = door_switches[door_pos]
		var all_switches_on = true
		for switch_pos in required_switches:
			if not switches.get(switch_pos, false):
				all_switches_on = false
				break
		
		doors[door_pos] = all_switches_on
		if is_instance_valid(door_bodies[door_pos]):
			door_bodies[door_pos].get_child(0).disabled = all_switches_on

func _update_gates():
	for plate_pos in plate_gates:
		var gate_pos = plate_gates[plate_pos]
		var gate_open = plates[plate_pos]
		gates[gate_pos] = gate_open
		if is_instance_valid(gate_bodies[gate_pos]):
			gate_bodies[gate_pos].get_child(0).disabled = gate_open

func has_switch_at(pos: Vector2i) -> bool:
	return switches.has(pos) or reset_switches.has(pos)

func has_pressure_plate_at(pos: Vector2i) -> bool: return plates.has(pos)

func _draw():
	var current_maze_size = get_maze_size()
	for y in current_maze_size.y:
		for x in current_maze_size.x:
			var rect = Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			draw_rect(rect, wall_color if grid[y][x] else path_color)
	_draw_switches()
	_draw_doors()
	_draw_pressure_plates()
	_draw_gates()

func _draw_switches():
	# Regular switches
	for pos in switches:
		var rect = Rect2(pos.x * cell_size + 8, pos.y * cell_size + 8, 16, 16)
		draw_rect(rect, Color.GREEN if switches[pos] else switch_color)
	# Reset switches
	for pos in reset_switches:
		var rect = Rect2(pos.x * cell_size + 8, pos.y * cell_size + 8, 16, 16)
		draw_rect(rect, reset_switch_color) # Always the same color

func _draw_doors():
	for pos in doors:
		if not doors[pos]:
			var rect = Rect2(pos.x * cell_size, pos.y * cell_size, cell_size, cell_size)
			var door_color_to_use = door_color
			if door_switches.has(pos) and door_switches[pos].size() > 1:
				door_color_to_use = multi_switch_door_color
			draw_rect(rect, door_color_to_use)

func _draw_pressure_plates():
	for pos in plates:
		var rect = Rect2(pos.x * cell_size + 4, pos.y * cell_size + 4, 24, 24)
		draw_rect(rect, Color.LIGHT_BLUE if plates[pos] else plate_color)

func _draw_gates():
	for pos in gates:
		if not gates[pos]:
			var rect = Rect2(pos.x * cell_size, pos.y * cell_size, cell_size, cell_size)
			draw_rect(rect, gate_color)

func _find_astar_path(start_pos: Vector2i, end_pos: Vector2i) -> Array:
	var open_set: Array[AStarPoint] = []
	var all_points: Dictionary = {}
	var start_point = AStarPoint.new(start_pos)
	start_point.g_score = 0
	start_point.h_score = _heuristic(start_pos, end_pos)
	start_point.f_score = start_point.h_score
	open_set.append(start_point)
	all_points[start_pos] = start_point

	while not open_set.is_empty():
		open_set.sort_custom(func(a, b): return a.f_score < b.f_score)
		var current_point = open_set.pop_front()
		if current_point.pos == end_pos: return _reconstruct_path(current_point)
		
		all_points.erase(current_point.pos)

		for neighbor_pos in _get_astar_neighbors(current_point.pos):
			if not all_points.has(neighbor_pos) or all_points[neighbor_pos].f_score == INF:
				var neighbor_point = all_points.get(neighbor_pos, AStarPoint.new(neighbor_pos))
				if not all_points.has(neighbor_pos): all_points[neighbor_pos] = neighbor_point
				
				var tentative_g_score = current_point.g_score + 1
				if tentative_g_score < neighbor_point.g_score:
					neighbor_point.parent = current_point
					neighbor_point.g_score = tentative_g_score
					neighbor_point.h_score = _heuristic(neighbor_pos, end_pos)
					neighbor_point.f_score = neighbor_point.g_score + neighbor_point.h_score
					if not open_set.has(neighbor_point): open_set.append(neighbor_point)
	return []

func _heuristic(a: Vector2i, b: Vector2i) -> float: return a.distance_to(b)

func _get_astar_neighbors(pos: Vector2i) -> Array:
	var neighbors: Array[Vector2i] = []
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor = pos + dir
		# Use the smarter path check for A*
		if is_path_at(neighbor, true):
			neighbors.append(neighbor)
	return neighbors

func _reconstruct_path(current_point: AStarPoint) -> Array:
	var path: Array[Vector2i] = [current_point.pos]
	var current = current_point
	while current.parent != null:
		current = current.parent
		path.push_front(current.pos)
	return path

func _on_goal_entered(body):
	if body is Player:
		print("Player reached the exit!")
		next_level()
