extends Node2D
class_name LevelLoader

# --- Scene & Asset Preloads ---
const GoalScene = preload("res://scenes/Goal.tscn")
const wall_sprite = preload("res://assets/art/wall.png")
const floor_sprite = preload("res://assets/art/floor.png")
const door_sprite = preload("res://assets/art/door.png")
const door_open_sprite = preload("res://assets/art/door_open.png")
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
var door_switches: Dictionary = {} # door_pos -> [switch_pos1, switch_pos2]
var plate_gates: Dictionary = {}   # gate_pos -> [plate_pos1, plate_pos2]

# --- Sprite Nodes ---
var tile_sprites: Dictionary = {} # pos -> sprite_node
var background_sprites: Array[Sprite2D] = []
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


func next_level():
	current_level_index = (current_level_index + 1)
	if current_level_index >= level_files.size():
		current_level_index = 0
	generate()

func generate():
	_clear_level_objects()
	if current_level_index >= level_files.size():
		return
		
	var success = _load_level_from_file(level_files[current_level_index])
	if success:
		_create_collision_bodies()
		_draw_level_sprites()
		_update_doors()
		_update_gates()
		level_generated.emit(player_start_pos)

func _load_level_from_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false

	# MODIFIED: Doors and gates now store arrays of positions
	var numbered_switches = {} # "1" -> [pos1, pos2]
	var numbered_doors = {}    # "1" -> [pos1, pos2]
	var numbered_plates = {}   # "1" -> [pos1, pos2]
	var numbered_gates = {}    # "1" -> [pos1, pos2]

	var lines = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()

	var max_grid_width = 0
	for line in lines:
		var current_grid_width = 0
		var i = 0
		while i < line.length():
			var char = line[i]
			var next_char = line[i+1] if i + 1 < line.length() else ' '
			if char.is_valid_int() and ['S', 'D', 'T', 'A'].has(next_char):
				i += 2
			else:
				i += 1
			current_grid_width += 1
		if current_grid_width > max_grid_width:
			max_grid_width = current_grid_width

	grid_size = Vector2i(max_grid_width, lines.size())
	
	grid.clear()
	for y in range(grid_size.y):
		grid.append([])
		grid[y].resize(grid_size.x)
		grid[y].fill(false)

	for y in range(lines.size()):
		var line = lines[y]
		var x = 0 
		var grid_x = 0
		while x < line.length():
			var char = line[x]
			var pos = Vector2i(grid_x, y)
			
			var is_numeric = char.is_valid_int()
			var next_char = line[x+1] if x + 1 < line.length() else ' '
			
			if is_numeric and ['S', 'D', 'T', 'A'].has(next_char):
				match next_char:
					'S':
						if not numbered_switches.has(char): numbered_switches[char] = []
						numbered_switches[char].append(pos)
						switches[pos] = false
					'D':
						# MODIFIED: Append to list instead of overwriting
						if not numbered_doors.has(char): numbered_doors[char] = []
						numbered_doors[char].append(pos)
						doors[pos] = false
					'T':
						if not numbered_plates.has(char): numbered_plates[char] = []
						numbered_plates[char].append(pos)
						plates[pos] = false
					'A':
						# MODIFIED: Append to list instead of overwriting
						if not numbered_gates.has(char): numbered_gates[char] = []
						numbered_gates[char].append(pos)
						gates[pos] = false
				x += 2
			else:
				match char:
					'#': grid[y][grid_x] = true
					'P': player_start_pos = pos
					'G': _create_goal(pos)
					'S': switches[pos] = false
					'D': doors[pos] = false
					'R': reset_switches.append(pos)
					'T': plates[pos] = false
					'A': gates[pos] = false
					' ': pass
				x += 1
			
			grid_x += 1

	# MODIFIED: Loop through door positions to link them
	for num_char in numbered_doors:
		if numbered_switches.has(num_char):
			for d_pos in numbered_doors[num_char]:
				door_switches[d_pos] = numbered_switches[num_char]
			
	# MODIFIED: Loop through gate positions to link them
	for num_char in numbered_gates:
		if numbered_plates.has(num_char):
			for g_pos in numbered_gates[num_char]:
				plate_gates[g_pos] = numbered_plates[num_char]

	# --- Auto-link un-numbered switches and doors ---
	var unlinked_switches = switches.keys().filter(func(s):
		for door in door_switches:
			if door_switches[door].has(s): return false
		return true
	)
	var unlinked_doors = doors.keys().filter(func(d): return not door_switches.has(d))
	
	for d_pos in unlinked_doors:
		var best_s_pos = Vector2i.ZERO
		var min_dist = INF
		for s_pos in unlinked_switches:
			var d = d_pos.distance_squared_to(s_pos)
			if d < min_dist:
				min_dist = d
				best_s_pos = s_pos
		if best_s_pos != Vector2i.ZERO:
			door_switches[d_pos] = [best_s_pos]
			unlinked_switches.erase(best_s_pos)

	# --- Auto-link un-numbered plates and gates ---
	var unlinked_plates = plates.keys().filter(func(p):
		for gate in plate_gates:
			if plate_gates[gate].has(p): return false
		return true
	)
	var unlinked_gates = gates.keys().filter(func(g): return not plate_gates.has(g))

	for p_pos in unlinked_plates:
		var best_g_pos = Vector2i.ZERO
		var min_dist = INF
		for g_pos in unlinked_gates:
			var d = p_pos.distance_squared_to(g_pos)
			if d < min_dist:
				min_dist = d
				best_g_pos = g_pos
		if best_g_pos != Vector2i.ZERO:
			if not plate_gates.has(best_g_pos):
				plate_gates[best_g_pos] = []
			plate_gates[best_g_pos].append(p_pos)
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

	for sprite in background_sprites:
		if is_instance_valid(sprite): sprite.queue_free()
	background_sprites.clear()
	
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
		var was_open = doors.get(door_pos, false)
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
			
		if door_bodies.has(door_pos) and is_instance_valid(door_bodies[door_pos]):
			door_bodies[door_pos].get_child(0).disabled = is_open
		
		_update_door_sprite(door_pos)

func _update_gates():
	for gate_pos in plate_gates:
		var was_open = gates.get(gate_pos, false)
		var required_plates = plate_gates[gate_pos]
		var all_plates_on = true
		for plate_pos in required_plates:
			if not plates.get(plate_pos, false):
				all_plates_on = false
				break
		
		var is_open = all_plates_on
		gates[gate_pos] = is_open

		if is_open and not was_open:
			if is_instance_valid(door_open_sound): door_open_sound.play()
		elif not is_open and was_open:
			if is_instance_valid(door_close_sound): door_close_sound.play()

		if gate_bodies.has(gate_pos) and is_instance_valid(gate_bodies[gate_pos]):
			gate_bodies[gate_pos].get_child(0).disabled = is_open
		
		_update_gate_sprite(gate_pos)

func _draw_level_sprites():
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var pos = Vector2i(x, y)
			if grid[y][x]:
				_create_sprite_at(pos, wall_sprite, -1, false) # Walls
			else:
				_create_sprite_at(pos, floor_sprite, -1, false) # Floor

	if is_instance_valid(goal_instance):
		_create_sprite_at(_world_to_grid(goal_instance.position), floor_sprite, -1, false)
	
	for pos in plates: _create_sprite_at(pos, plate_off_sprite, 0)
	for pos in switches: _create_sprite_at(pos, switch_off_sprite, 0)
	for pos in reset_switches: _create_sprite_at(pos, reset_switch_sprite, 0)
	for pos in doors: _create_sprite_at(pos, door_sprite, 0)
	for pos in gates: _create_sprite_at(pos, gate_sprite, 0)

func _create_sprite_at(pos: Vector2i, texture: Texture2D, z_index = 0, store = true):
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.position = Vector2(pos.x * cell_size + cell_size / 2, pos.y * cell_size + cell_size / 2)
	sprite.z_index = z_index
	add_child(sprite)
	if store:
		tile_sprites[pos] = sprite
	else:
		background_sprites.append(sprite)


func _update_switch_sprites():
	for pos in switches:
		if tile_sprites.has(pos):
			tile_sprites[pos].texture = switch_on_sprite if switches[pos] else switch_off_sprite

func _update_door_sprite(pos: Vector2i):
	if tile_sprites.has(pos):
		tile_sprites[pos].texture = door_open_sprite if doors.get(pos, false) else door_sprite

func _update_gate_sprite(pos: Vector2i):
	if tile_sprites.has(pos):
		tile_sprites[pos].visible = not gates.get(pos, false)

func _update_plate_sprite(pos: Vector2i):
	if tile_sprites.has(pos):
		tile_sprites[pos].texture = plate_on_sprite if plates.get(pos, false) else plate_off_sprite

func has_switch_at(pos: Vector2i) -> bool:
	return switches.has(pos) or reset_switches.has(pos)

func has_pressure_plate_at(pos: Vector2i) -> bool: return plates.has(pos)

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / cell_size), int(world_pos.y / cell_size))

func _on_goal_entered(body):
	if body is Player:
		if is_instance_valid(level_completed_sound):
			level_completed_sound.play()
		# Wait for a short duration instead of the full sound length
		await get_tree().create_timer(0.5).timeout
		next_level()
