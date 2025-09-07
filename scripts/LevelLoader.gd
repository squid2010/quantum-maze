extends Node2D
class_name LevelLoader

# --- Goal Scene ---
const GoalScene = preload("res://scenes/Goal.tscn")
var goal_instance = null
# ------------------

# --- Level Progression ---
var level_files: Array[String] = []
var current_level_index: int = 0
# -------------------------

@export var cell_size: int = 32

# Colors
@export var wall_color: Color = Color.BLACK
@export var path_color: Color = Color.WHITE
@export var switch_color: Color = Color.YELLOW
@export var reset_switch_color: Color = Color.CYAN
@export var door_color: Color = Color.RED
@export var multi_switch_door_color: Color = Color.ORANGE
@export var plate_color: Color = Color.BLUE
@export var gate_color: Color = Color.PURPLE

# Core data
var grid: Array[Array] = []
var grid_size: Vector2i = Vector2i.ZERO
var player_start_pos: Vector2i = Vector2i.ONE

# Puzzle elements
var switches: Dictionary = {} # switch_pos -> is_on
var reset_switches: Array[Vector2i] = []
var doors: Dictionary = {}    # door_pos -> is_open
var plates: Dictionary = {}   # plate_pos -> is_on
var gates: Dictionary = {}    # gate_pos -> is_open

# Puzzle connections
# For numbered switches/doors: { door_pos -> [switch_pos1, switch_pos2] }
var door_switches: Dictionary = {}
# For temporal puzzles (T -> A): { plate_pos -> gate_pos }
var plate_gates: Dictionary = {}

# Collision bodies
var wall_bodies: Array[StaticBody2D] = []
var door_bodies: Dictionary = {}
var gate_bodies: Dictionary = {}

# Signal
signal level_generated(player_start_position: Vector2i)

func _ready():
	_scan_for_levels()
	if not level_files.is_empty():
		generate()
	else:
		print("ERROR: No level files found in res://levels/. Please create level files like 'level1.txt'.")

func _scan_for_levels():
	level_files.clear()
	var dir = DirAccess.open("res://levels")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".txt"):
				# --- FIX IS HERE ---
				# Construct the full path by joining the directory path and the file name.
				level_files.append(dir.get_current_dir().path_join(file_name))
			file_name = dir.get_next()
		level_files.sort() # Ensure a consistent order (level1, level2, etc.)
		print("Found levels: ", level_files)
	else:
		print("Could not open directory res://levels/")


func next_level():
	print("Level complete! Loading next level...")
	current_level_index = (current_level_index + 1)
	if current_level_index >= level_files.size():
		print("All levels completed! Looping back to first level.")
		current_level_index = 0
	generate()

func generate():
	_clear_level_objects()
	if current_level_index >= level_files.size():
		print("Error: Invalid level index.")
		return
		
	var success = _load_level_from_file(level_files[current_level_index])
	if success:
		_create_collision_bodies()
		queue_redraw()
		level_generated.emit(player_start_pos)
		print("Successfully loaded level: ", level_files[current_level_index])

func _load_level_from_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("ERROR: Could not open level file: ", file_path)
		return false

	# Temporary storage for linking numbered puzzles
	var numbered_switches = {} # { "1" -> [pos1, pos2] }
	var numbered_doors = {}    # { "1" -> pos }

	var lines = []
	var max_width = 0
	while not file.eof_reached():
		var line = file.get_line()
		lines.append(line)
		if line.length() > max_width:
			max_width = line.length()
	
	grid_size = Vector2i(max_width, lines.size())
	
	# Initialize grid
	grid.clear()
	for y in range(grid_size.y):
		grid.append([])
		for x in range(grid_size.x):
			grid[y].append(false) # Default to path

	# Parse file content
	for y in range(lines.size()):
		var line = lines[y]
		for x in range(line.length()):
			var char = line[x]
			var pos = Vector2i(x, y)
			
			match char:
				'#': # Wall
					grid[y][x] = true
				'P': # Player Start
					player_start_pos = pos
				'G': # Goal
					_create_goal(pos)
				'S': # Simple Switch
					switches[pos] = false
				'D': # Simple Door
					doors[pos] = false
				'R': # Reset Switch
					reset_switches.append(pos)
				'T': # Temporal Plate
					plates[pos] = false
				'A': # Temporal Gate
					gates[pos] = false
				'1', '2', '3', '4', '5', '6', '7', '8', '9':
					# Could be a switch or a door
					var next_char = line[x+1] if x + 1 < line.length() else ' '
					if next_char == 'S':
						if not numbered_switches.has(char): numbered_switches[char] = []
						numbered_switches[char].append(pos)
						switches[pos] = false
					elif next_char == 'D':
						numbered_doors[char] = pos
						doors[pos] = false
					
	# --- Link Puzzles ---
	# Link simple Switch to simple Door (find the nearest one)
	var simple_switches = switches.keys().filter(func(p): return not door_switches.values().has(p))
	var simple_doors = doors.keys().filter(func(p): return not door_switches.has(p))
	if not simple_switches.is_empty() and not simple_doors.is_empty():
		door_switches[simple_doors[0]] = [simple_switches[0]]
		
	# Link numbered switches to doors
	for num_char in numbered_doors:
		var d_pos = numbered_doors[num_char]
		if numbered_switches.has(num_char):
			door_switches[d_pos] = numbered_switches[num_char]

	# Link temporal plates to gates (find nearest)
	var unlinked_plates = plates.keys().filter(func(p): return not plate_gates.has(p))
	var unlinked_gates = gates.keys().filter(func(p): return not plate_gates.values().has(p))
	for p_pos in unlinked_plates:
		var best_g_pos = Vector2i.ZERO
		var min_dist = INF
		for g_pos in unlinked_gates:
			var d = p_pos.distance_squared_to(g_pos)
			if d < min_dist:
				min_dist = d
				best_g_pos = g_pos
		if best_g_pos != Vector2i.ZERO:
			plate_gates[p_pos] = best_g_pos
			unlinked_gates.erase(best_g_pos)
			
	return true

func _create_goal(pos: Vector2i):
	goal_instance = GoalScene.instantiate()
	goal_instance.position = Vector2(pos.x * cell_size, pos.y * cell_size)
	goal_instance.body_entered.connect(_on_goal_entered)
	add_child(goal_instance)

func get_maze_size() -> Vector2i: return grid_size
func get_current_level_index() -> int: return current_level_index

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
		
	grid.clear()
	switches.clear()
	reset_switches.clear()
	doors.clear()
	plates.clear()
	gates.clear()
	door_switches.clear()
	plate_gates.clear()

func _create_collision_bodies():
	for y in range(grid_size.y):
		for x in range(grid_size.x):
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

func is_wall_at(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= grid_size.x or pos.y < 0 or pos.y >= grid_size.y:
		return true
	return grid[pos.y][pos.x]

func toggle_switch(pos: Vector2i):
	if reset_switches.has(pos):
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
	if grid.is_empty(): return
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var rect = Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			draw_rect(rect, wall_color if grid[y][x] else path_color)
	_draw_switches()
	_draw_doors()
	_draw_pressure_plates()
	_draw_gates()

func _draw_switches():
	for pos in switches:
		var rect = Rect2(pos.x * cell_size + 8, pos.y * cell_size + 8, 16, 16)
		draw_rect(rect, Color.GREEN if switches[pos] else switch_color)
	for pos in reset_switches:
		var rect = Rect2(pos.x * cell_size + 8, pos.y * cell_size + 8, 16, 16)
		draw_rect(rect, reset_switch_color)

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

func _on_goal_entered(body):
	if body is Player:
		print("Player reached the goal!")
		next_level()
