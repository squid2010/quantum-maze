extends Node2D
class_name LevelLoader

# --- Scene & Asset Preloads ---
const GoalScene = preload("res://scenes/Goal.tscn")
const wall_sprite = preload("res://assets/art/wall.png")
const floor_sprite = preload("res://assets/art/floor.png")
const door_sprite = preload("res://assets/art/door.png")
const gate_sprite = preload("res://assets/art/gate.png")
const switch_on_sprite = preload("res://assets/art/switch_on.png")
const switch_off_sprite = preload("res://assets/art/switch_off.png")
const reset_switch_sprite = preload("res://assets/art/reset_switch.png")
const plate_on_sprite = preload("res://assets/art/plate_on.png")
const plate_off_sprite = preload("res://assets/art/plate_off.png")
# ------------------------------

var goal_instance = null

# --- Level Progression ---
var level_files: Array[String] = []
var current_level_index: int = 0
# -------------------------

@export var cell_size: int = 32

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
var door_switches: Dictionary = {}
var plate_gates: Dictionary = {}

# --- Sprite Nodes ---
var tile_sprites: Dictionary = {} # pos -> sprite_node
# --------------------

# Collision bodies
var wall_bodies: Array[StaticBody2D] = []
var door_bodies: Dictionary = {}
var gate_bodies: Dictionary = {}

# --- Audio Players ---
@onready var plate_on_sound: AudioStreamPlayer = $PlateOnSound
@onready var plate_off_sound: AudioStreamPlayer = $PlateOffSound
@onready var door_open_sound: AudioStreamPlayer = $DoorOpenSound
@onready var door_close_sound: AudioStreamPlayer = $DoorCloseSound
@onready var switch_on_sound: AudioStreamPlayer = $SwitchOnSound
@onready var switch_off_sound: AudioStreamPlayer = $SwitchOffSound
@onready var level_completed_sound: AudioStreamPlayer = $LevelCompletedSound
# --------------------------

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
				level_files.append(dir.get_current_dir().path_join(file_name))
			file_name = dir.get_next()
		level_files.sort() 
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
		_draw_level_sprites()
		level_generated.emit(player_start_pos)
		print("Successfully loaded level: ", level_files[current_level_index])

func _load_level_from_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("ERROR: Could not open level file: ", file_path)
		return false

	var numbered_switches = {}
	var numbered_doors = {}

	var lines = []
	var max_width = 0
	while not file.eof_reached():
		var line = file.get_line()
		lines.append(line)
		if line.length() > max_width:
			max_width = line.length()
	
	grid_size = Vector2i(max_width, lines.size())
	
	grid.clear()
	for y in range(grid_size.y):
		grid.append([])
		for x in range(grid_size.x):
			grid[y].append(false)

	for y in range(lines.size()):
		var line = lines[y]
		for x in range(line.length()):
			var char = line[x]
			var pos = Vector2i(x, y)
			
			match char:
				'#': grid[y][x] = true
				'P': player_start_pos = pos
				'G': _create_goal(pos)
				'S': switches[pos] = false
				'D': doors[pos] = false
				'R': reset_switches.append(pos)
				'T': plates[pos] = false
				'A': gates[pos] = false
				'1', '2', '3', '4', '5', '6', '7', '8', '9':
					var next_char = line[x+1] if x + 1 < line.length() else ' '
					if next_char == 'S':
						if not numbered_switches.has(char): numbered_switches[char] = []
						numbered_switches[char].append(pos)
						switches[pos] = false
					elif next_char == 'D':
						numbered_doors[char] = pos
						doors[pos] = false
					
	var simple_switches = switches.keys().filter(func(p): return not door_switches.values().has(p))
	var simple_doors = doors.keys().filter(func(p): return not door_switches.has(p))
	if not simple_switches.is_empty() and not simple_doors.is_empty():
		door_switches[simple_doors[0]] = [simple_switches[0]]
		
	for num_char in numbered_doors:
		var d_pos = numbered_doors[num_char]
		if numbered_switches.has(num_char):
			door_switches[d_pos] = numbered_switches[num_char]

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
	# The goal scene has its own sprite, so we store a reference to the instance itself for cleanup
	tile_sprites[pos] = goal_instance

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

	for pos in tile_sprites:
		if is_instance_valid(tile_sprites[pos]):
			tile_sprites[pos].queue_free()
	tile_sprites.clear()
		
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
		if is_instance_valid(switch_off_sound):
			switch_off_sound.play()
		for switch_pos in switches:
			switches[switch_pos] = false
		print("Reset switch activated!")
	elif switches.has(pos):
		switches[pos] = not switches[pos]
		if switches[pos]:
			if is_instance_valid(switch_on_sound): switch_on_sound.play()
		else:
			if is_instance_valid(switch_off_sound): switch_off_sound.play()
	
	_update_doors()
	_update_switch_sprites()
	
func activate_pressure_plate(pos: Vector2i):
	if plates.has(pos):
		if not plates[pos]:
			if is_instance_valid(plate_on_sound):
				plate_on_sound.play()
		plates[pos] = true
		_update_gates()
		_update_plate_sprite(pos)

func deactivate_pressure_plate(pos: Vector2i):
	if plates.has(pos):
		if plates[pos]:
			if is_instance_valid(plate_off_sound):
				plate_off_sound.play()
		plates[pos] = false
		_update_gates()
		_update_plate_sprite(pos)

func _update_doors():
	for door_pos in door_switches:
		var was_open = doors[door_pos]
		var required_switches = door_switches[door_pos]
		var all_switches_on = true
		for switch_pos in required_switches:
			if not switches.get(switch_pos, false):
				all_switches_on = false
				break
		
		var is_open = all_switches_on
		doors[door_pos] = is_open
		
		if is_open and not was_open:
			if is_instance_valid(door_open_sound): door_open_sound.play()
		elif not is_open and was_open:
			if is_instance_valid(door_close_sound): door_close_sound.play()
			
		if is_instance_valid(door_bodies[door_pos]):
			door_bodies[door_pos].get_child(0).disabled = is_open
		
		_update_door_sprite(door_pos)

func _update_gates():
	for plate_pos in plate_gates:
		var gate_pos = plate_gates[plate_pos]
		var was_open = gates[gate_pos]
		var is_open = plates[plate_pos]
		gates[gate_pos] = is_open

		if is_open and not was_open:
			if is_instance_valid(door_open_sound): door_open_sound.play()
		elif not is_open and was_open:
			if is_instance_valid(door_close_sound): door_close_sound.play()

		if is_instance_valid(gate_bodies[gate_pos]):
			gate_bodies[gate_pos].get_child(0).disabled = is_open
		
		_update_gate_sprite(gate_pos)

func _draw_level_sprites():
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var pos = Vector2i(x, y)
			if grid[y][x]:
				_create_sprite_at(pos, wall_sprite, 1, false) # Walls
			elif not goal_instance or not pos == _world_to_grid(goal_instance.position):
				_create_sprite_at(pos, floor_sprite, -1, false) # Floor
	
	for pos in plates: _create_sprite_at(pos, plate_off_sprite, 0)
	for pos in switches: _create_sprite_at(pos, switch_off_sprite)
	for pos in reset_switches: _create_sprite_at(pos, reset_switch_sprite)
	for pos in doors: _create_sprite_at(pos, door_sprite)
	for pos in gates: _create_sprite_at(pos, gate_sprite)

func _create_sprite_at(pos: Vector2i, texture: Texture2D, z_index = 1, store = true):
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.position = Vector2(pos.x * cell_size + cell_size / 2, pos.y * cell_size + cell_size / 2)
	sprite.z_index = z_index
	add_child(sprite)
	if store:
		tile_sprites[pos] = sprite
	else:
		# For non-interactive sprites like walls and floor, just store them in a temp array for cleanup
		if not tile_sprites.has("background"): tile_sprites["background"] = []
		tile_sprites["background"].append(sprite)


func _update_switch_sprites():
	for pos in switches:
		if tile_sprites.has(pos):
			tile_sprites[pos].texture = switch_on_sprite if switches[pos] else switch_off_sprite

func _update_door_sprite(pos: Vector2i):
	if tile_sprites.has(pos):
		tile_sprites[pos].visible = not doors[pos]

func _update_gate_sprite(pos: Vector2i):
	if tile_sprites.has(pos):
		tile_sprites[pos].visible = not gates[pos]

func _update_plate_sprite(pos: Vector2i):
	if tile_sprites.has(pos):
		tile_sprites[pos].texture = plate_on_sprite if plates[pos] else plate_off_sprite

func has_switch_at(pos: Vector2i) -> bool:
	return switches.has(pos) or reset_switches.has(pos)

func has_pressure_plate_at(pos: Vector2i) -> bool: return plates.has(pos)

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / cell_size), int(world_pos.y / cell_size))

func _on_goal_entered(body):
	if body is Player:
		print("Player reached the goal!")
		if is_instance_valid(level_completed_sound):
			level_completed_sound.play()
			await level_completed_sound.finished
		next_level()
