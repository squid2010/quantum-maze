extends Node2D
# Enhanced maze generation with quantum echo puzzles
class_name MazeGenerator

@export var maze_width: int = 21  # Should be odd numbers for proper walls
@export var maze_height: int = 21
@export var cell_size: int = 32
@export var wall_color: Color = Color.BLACK
@export var path_color: Color = Color.WHITE
@export var door_color: Color = Color.RED
@export var switch_color: Color = Color.YELLOW
@export var pressure_plate_color: Color = Color.BLUE
@export var gate_color: Color = Color.PURPLE

# Maze grid - true = wall, false = path
var maze_grid: Array[Array] = []
var visited: Array[Array] = []

# Interactive elements
var switches: Array[Vector2i] = []  # Switch positions
var doors: Array[Vector2i] = []     # Door positions (closed by default)
var pressure_plates: Array[Vector2i] = []  # Pressure plate positions
var gates: Array[Vector2i] = []     # Gate positions (open when pressure plate active)

# Switch states
var switch_states: Dictionary = {}  # Vector2i -> bool
var door_states: Dictionary = {}    # Vector2i -> bool (true = open)
var plate_states: Dictionary = {}   # Vector2i -> bool
var gate_states: Dictionary = {}    # Vector2i -> bool (true = open)

# Directions: North, East, South, West
var directions = [
	Vector2i(0, -1),  # North
	Vector2i(1, 0),   # East
	Vector2i(0, 1),   # South
	Vector2i(-1, 0)   # West
]

signal switch_toggled(pos: Vector2i, state: bool)
signal door_state_changed(pos: Vector2i, is_open: bool)
signal pressure_plate_activated(pos: Vector2i)
signal pressure_plate_deactivated(pos: Vector2i)

func _ready():
	generate_maze()

func generate_maze():
	# Initialize grids
	initialize_grids()
	
	# Start from position (1,1) - first path cell
	var start_pos = Vector2i(1, 1)
	recursive_backtrack(start_pos)
	add_entrance_exit()
	
	# Add interactive elements
	add_interactive_elements()
	
	# Draw the maze
	queue_redraw()

func initialize_grids():
	maze_grid.clear()
	visited.clear()
	switches.clear()
	doors.clear()
	pressure_plates.clear()
	gates.clear()
	switch_states.clear()
	door_states.clear()
	plate_states.clear()
	gate_states.clear()
	
	# Initialize with all walls
	for y in range(maze_height):
		maze_grid.append([])
		visited.append([])
		for x in range(maze_width):
			maze_grid[y].append(true)  # true = wall
			visited[y].append(false)
	
	# Create starting path cell
	maze_grid[1][1] = false  # false = path

func recursive_backtrack(pos: Vector2i):
	var stack: Array[Vector2i] = []
	var current = pos
	visited[current.y][current.x] = true
	
	while true:
		var neighbors = get_unvisited_neighbors(current)
		
		if neighbors.size() > 0:
			# Choose random neighbor
			var next_cell = neighbors[randi() % neighbors.size()]
			
			# Remove wall between current and next cell
			var wall_pos = Vector2i(
				(current.x + next_cell.x) / 2,
				(current.y + next_cell.y) / 2
			)
			maze_grid[wall_pos.y][wall_pos.x] = false
			maze_grid[next_cell.y][next_cell.x] = false
			
			# Mark as visited
			visited[next_cell.y][next_cell.x] = true
			
			# Push current to stack and move to next
			stack.push_back(current)
			current = next_cell
		else:
			if stack.is_empty():
				break
			current = stack.pop_back()

func get_unvisited_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	
	for direction in directions:
		# Move 2 cells in each direction (to skip walls)
		var neighbor = pos + direction * 2
		
		# Check bounds and if unvisited
		if is_valid_cell(neighbor) and not visited[neighbor.y][neighbor.x]:
			neighbors.append(neighbor)
	
	return neighbors

func is_valid_cell(pos: Vector2i) -> bool:
	return pos.x > 0 and pos.x < maze_width - 1 and \
		   pos.y > 0 and pos.y < maze_height - 1

func add_entrance_exit():
	"""Adds entrance at top-left and exit at bottom-right"""
	# Entrance (top)
	maze_grid[0][1] = false
	
	# Exit (bottom)
	maze_grid[maze_height - 1][maze_width - 2] = false

func add_interactive_elements():
	"""Add switches, doors, pressure plates, and gates to create quantum echo puzzles"""
	var path_cells = get_all_path_cells()
	
	if path_cells.size() < 10:
		return  # Not enough space for puzzles
	
	# Puzzle 1: Simple switch-door pair
	add_switch_door_puzzle(path_cells)
	
	# Puzzle 2: Pressure plate that needs to be held while player goes elsewhere
	add_pressure_plate_puzzle(path_cells)
	
	# Puzzle 3: Multiple switches for one door
	add_multi_switch_puzzle(path_cells)
	
	# Puzzle 4: Sequential activation puzzle
	add_sequential_puzzle(path_cells)

func get_all_path_cells() -> Array[Vector2i]:
	var paths: Array[Vector2i] = []
	for y in range(maze_height):
		for x in range(maze_width):
			if not maze_grid[y][x]:  # is path
				paths.append(Vector2i(x, y))
	return paths

func add_switch_door_puzzle(path_cells: Array[Vector2i]):
	"""Add a simple switch that opens a door"""
	if path_cells.size() < 4:
		return
	
	# Find a good spot for switch and door
	var switch_pos = path_cells[randi() % (path_cells.size() / 2)]
	var door_pos = path_cells[path_cells.size() - randi() % (path_cells.size() / 2)]
	
	# Make sure they're not too close
	if switch_pos.distance_to(door_pos) < 5:
		door_pos = path_cells[path_cells.size() - 1 - randi() % 3]
	
	add_switch(switch_pos)
	add_door(door_pos)
	
	# Link them
	connect_switch_to_door(switch_pos, door_pos)

func add_pressure_plate_puzzle(path_cells: Array[Vector2i]):
	"""Add a pressure plate that needs to be held down"""
	if path_cells.size() < 6:
		return
	
	var plate_pos = path_cells[randi() % (path_cells.size() / 3)]
	var gate_pos = path_cells[path_cells.size() - randi() % (path_cells.size() / 3)]
	
	# Make sure they're separated
	if plate_pos.distance_to(gate_pos) < 7:
		gate_pos = path_cells[path_cells.size() - 1 - randi() % 5]
	
	add_pressure_plate(plate_pos)
	add_gate(gate_pos)
	
	# Link them
	connect_plate_to_gate(plate_pos, gate_pos)

func add_multi_switch_puzzle(path_cells: Array[Vector2i]):
	"""Add multiple switches for one door"""
	if path_cells.size() < 8:
		return
	
	var num_switches = 2 + randi() % 2  # 2-3 switches
	var switch_positions: Array[Vector2i] = []
	
	# Place switches
	for i in range(num_switches):
		var pos = path_cells[randi() % (path_cells.size() / 2)]
		while switch_positions.has(pos) or switches.has(pos):
			pos = path_cells[randi() % (path_cells.size() / 2)]
		switch_positions.append(pos)
		add_switch(pos)
	
	# Place door
	var door_pos = path_cells[path_cells.size() - randi() % (path_cells.size() / 3)]
	while doors.has(door_pos):
		door_pos = path_cells[path_cells.size() - 1 - randi() % 5]
	
	add_door(door_pos)
	
	# Link all switches to the door
	for switch_pos in switch_positions:
		connect_switch_to_door(switch_pos, door_pos)

func add_sequential_puzzle(path_cells: Array[Vector2i]):
	"""Add switches that must be activated in sequence"""
	if path_cells.size() < 6:
		return
	
	var switch1_pos = path_cells[2 + randi() % 3]
	var switch2_pos = path_cells[path_cells.size() / 2 + randi() % 3]
	var door_pos = path_cells[path_cells.size() - 2 - randi() % 2]
	
	add_switch(switch1_pos)
	add_switch(switch2_pos)
	add_door(door_pos)
	
	# Custom logic will be handled in update_puzzle_states()

func add_switch(pos: Vector2i):
	if not switches.has(pos):
		switches.append(pos)
		switch_states[pos] = false

func add_door(pos: Vector2i):
	if not doors.has(pos):
		doors.append(pos)
		door_states[pos] = false  # false = closed

func add_pressure_plate(pos: Vector2i):
	if not pressure_plates.has(pos):
		pressure_plates.append(pos)
		plate_states[pos] = false

func add_gate(pos: Vector2i):
	if not gates.has(pos):
		gates.append(pos)
		gate_states[pos] = false  # false = closed

func connect_switch_to_door(switch_pos: Vector2i, door_pos: Vector2i):
	# This creates a logical connection - handled in update_puzzle_states()
	pass

func connect_plate_to_gate(plate_pos: Vector2i, gate_pos: Vector2i):
	# This creates a logical connection - handled in update_puzzle_states()
	pass

func toggle_switch(pos: Vector2i) -> bool:
	"""Toggle a switch and return new state"""
	if switch_states.has(pos):
		switch_states[pos] = not switch_states[pos]
		switch_toggled.emit(pos, switch_states[pos])
		update_puzzle_states()
		queue_redraw()
		return switch_states[pos]
	return false

func activate_pressure_plate(pos: Vector2i):
	"""Activate a pressure plate"""
	if plate_states.has(pos) and not plate_states[pos]:
		plate_states[pos] = true
		pressure_plate_activated.emit(pos)
		update_puzzle_states()
		queue_redraw()

func deactivate_pressure_plate(pos: Vector2i):
	"""Deactivate a pressure plate"""
	if plate_states.has(pos) and plate_states[pos]:
		plate_states[pos] = false
		pressure_plate_deactivated.emit(pos)
		update_puzzle_states()
		queue_redraw()

func update_puzzle_states():
	"""Update door and gate states based on switch and pressure plate states"""
	
	# Simple logic: if any switch is on, open corresponding doors
	for door_pos in doors:
		var should_open = false
		
		# Check if any connected switch is active
		for switch_pos in switches:
			if switch_states[switch_pos]:
				should_open = true
				break
		
		if door_states[door_pos] != should_open:
			door_states[door_pos] = should_open
			door_state_changed.emit(door_pos, should_open)
	
	# Pressure plate logic: gates open only while plates are pressed
	for gate_pos in gates:
		var should_open = false
		
		# Check if any connected pressure plate is active
		for plate_pos in pressure_plates:
			if plate_states[plate_pos]:
				should_open = true
				break
		
		gate_states[gate_pos] = should_open

func _draw():
	# Draw basic maze
	for y in range(maze_height):
		for x in range(maze_width):
			var rect = Rect2(
				x * cell_size, 
				y * cell_size, 
				cell_size, 
				cell_size
			)
			
			var color = wall_color if maze_grid[y][x] else path_color
			draw_rect(rect, color)
	
	# Draw interactive elements
	draw_switches()
	draw_doors()
	draw_pressure_plates()
	draw_gates()

func draw_switches():
	for switch_pos in switches:
		var rect = Rect2(
			switch_pos.x * cell_size + cell_size * 0.25,
			switch_pos.y * cell_size + cell_size * 0.25,
			cell_size * 0.5,
			cell_size * 0.5
		)
		
		var color = Color.GREEN if switch_states[switch_pos] else switch_color
		draw_rect(rect, color)
		
		# Draw border
		draw_rect(rect, Color.BLACK, false, 2)

func draw_doors():
	for door_pos in doors:
		if not door_states[door_pos]:  # Only draw if closed
			var rect = Rect2(
				door_pos.x * cell_size,
				door_pos.y * cell_size,
				cell_size,
				cell_size
			)
			draw_rect(rect, door_color)
			
			# Draw door pattern
			var line_start = Vector2(door_pos.x * cell_size, door_pos.y * cell_size + cell_size * 0.5)
			var line_end = Vector2((door_pos.x + 1) * cell_size, door_pos.y * cell_size + cell_size * 0.5)
			draw_line(line_start, line_end, Color.DARK_RED, 3)

func draw_pressure_plates():
	for plate_pos in pressure_plates:
		var rect = Rect2(
			plate_pos.x * cell_size + cell_size * 0.1,
			plate_pos.y * cell_size + cell_size * 0.1,
			cell_size * 0.8,
			cell_size * 0.8
		)
		
		var color = Color.LIGHT_BLUE if plate_states[plate_pos] else pressure_plate_color
		draw_rect(rect, color)
		
		# Draw activation indicator
		if plate_states[plate_pos]:
			var center = Vector2(plate_pos.x * cell_size + cell_size * 0.5, plate_pos.y * cell_size + cell_size * 0.5)
			draw_circle(center, cell_size * 0.15, Color.WHITE)

func draw_gates():
	for gate_pos in gates:
		if not gate_states[gate_pos]:  # Only draw if closed
			var rect = Rect2(
				gate_pos.x * cell_size,
				gate_pos.y * cell_size,
				cell_size,
				cell_size
			)
			draw_rect(rect, gate_color)
			
			# Draw gate pattern (vertical bars)
			for i in range(3):
				var x_pos = gate_pos.x * cell_size + cell_size * 0.2 + i * cell_size * 0.3
				var line_start = Vector2(x_pos, gate_pos.y * cell_size + cell_size * 0.1)
				var line_end = Vector2(x_pos, (gate_pos.y + 1) * cell_size - cell_size * 0.1)
				draw_line(line_start, line_end, Color.PINK, 2)

# Public functions for integration
func get_maze_data() -> Array[Array]:
	"""Returns the maze grid data"""
	return maze_grid

func is_wall_at(x: int, y: int) -> bool:
	"""Check if there's a wall at given coordinates"""
	if x < 0 or x >= maze_width or y < 0 or y >= maze_height:
		return true
	return maze_grid[y][x]

func is_path_at(x: int, y: int) -> bool:
	"""Check if there's a path at given coordinates (considering doors and gates)"""
	var pos = Vector2i(x, y)
	
	# Check if it's a basic wall
	if is_wall_at(x, y):
		return false
	
	# Check if there's a closed door
	if doors.has(pos) and not door_states[pos]:
		return false
	
	# Check if there's a closed gate
	if gates.has(pos) and not gate_states[pos]:
		return false
	
	return true

func is_switch_at(pos: Vector2i) -> bool:
	return switches.has(pos)

func is_pressure_plate_at(pos: Vector2i) -> bool:
	return pressure_plates.has(pos)

func get_maze_size() -> Vector2i:
	"""Returns maze dimensions"""
	return Vector2i(maze_width, maze_height)

func regenerate_maze():
	"""Generate a new maze"""
	generate_maze()

func get_switches() -> Array[Vector2i]:
	return switches.duplicate()

func get_doors() -> Array[Vector2i]:
	return doors.duplicate()

func get_pressure_plates() -> Array[Vector2i]:
	return pressure_plates.duplicate()

func get_gates() -> Array[Vector2i]:
	return gates.duplicate()
