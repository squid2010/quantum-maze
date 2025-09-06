extends Sprite2D
class_name QuantumEcho

@export var cell_size: int = 32

enum State { PAUSED, MOVING, FINISHED }
var state: State = State.PAUSED

var path: Array[Vector2i] = []
var timings: Array[float] = []
var current_path_index: int = 0

var grid_pos: Vector2i
var last_grid_pos: Vector2i
var target_world_pos: Vector2
var start_world_pos: Vector2

var timer: float = 0.0
var current_duration: float = 0.0

var player_ref: Player
var maze_ref: MazeGenerator

func setup(echo_path: Array[Vector2i], echo_timings: Array[float], player: Player, maze: MazeGenerator, original_sprite: Sprite2D):
	if echo_path.is_empty():
		_finish_echo()
		return

	path = echo_path.duplicate()
	timings = echo_timings.duplicate()
	player_ref = player
	maze_ref = maze
	
	# Copy sprite properties
	texture = original_sprite.texture
	scale = original_sprite.get_parent().scale
	modulate = Color(0.7, 1.0, 1.0, 0.6)
	
	# Initialize at the first path position
	current_path_index = 0
	grid_pos = path[0]
	last_grid_pos = grid_pos
	position = _grid_to_world(grid_pos)
	
	# Start the first pause
	_start_pause()

func _ready():
	# Check initial pressure plate
	if maze_ref and maze_ref.has_pressure_plate_at(grid_pos):
		player_ref.echo_entered_pressure_plate(grid_pos)

func _process(delta):
	if state == State.FINISHED:
		return

	timer += delta
	
	if state == State.PAUSED:
		if timer >= current_duration:
			# Pause is over, start moving to the next point
			_start_move()

	elif state == State.MOVING:
		var progress = 0.0
		if current_duration > 0:
			progress = clamp(timer / current_duration, 0.0, 1.0)
		else:
			progress = 1.0 # Instantly complete if duration is zero
		
		# Smooth interpolation to target
		position = start_world_pos.lerp(target_world_pos, _ease_in_out(progress))
		
		# Update grid position during movement
		var new_grid_pos = _world_to_grid(position)
		if new_grid_pos != last_grid_pos:
			_handle_position_change(last_grid_pos, new_grid_pos)
			last_grid_pos = new_grid_pos
		
		# Check if movement is complete
		if progress >= 1.0:
			position = target_world_pos
			grid_pos = path[current_path_index]
			last_grid_pos = grid_pos
			
			# Handle final position change
			_handle_position_change(_world_to_grid(start_world_pos), grid_pos)
			
			# Start the pause at the new location
			_start_pause()

func _start_pause():
	timer = 0.0
	state = State.PAUSED
	
	# The time recorded at an index is how long the player *stayed* there.
	if current_path_index < timings.size():
		current_duration = timings[current_path_index]
		print("Echo pausing at ", path[current_path_index], " for ", current_duration, " seconds")
	else:
		# If we've run out of timings, it means this is the last spot. End after a brief moment.
		current_duration = 0.1
		print("Echo reached end of timings at ", path[current_path_index])
		# Create a timer to finish, as there's no subsequent move to trigger the next state.
		var final_timer = get_tree().create_timer(current_duration)
		await final_timer.timeout
		_finish_echo()


func _start_move():
	# Move to the *next* index in the path
	current_path_index += 1
	
	if current_path_index >= path.size():
		_finish_echo()
		return
		
	timer = 0.0
	state = State.MOVING
	
	# The duration for the visual movement between cells is a fixed short time.
	current_duration = 0.2
	
	# Set start and end points for the interpolation
	start_world_pos = position
	target_world_pos = _grid_to_world(path[current_path_index])
	
	print("Echo moving to ", path[current_path_index])


func _ease_in_out(t: float) -> float:
	"""Smooth easing function for more natural movement"""
	return t * t * (3.0 - 2.0 * t)

func _handle_position_change(old_pos: Vector2i, new_pos: Vector2i):
	if old_pos == new_pos:
		return
		
	if maze_ref.has_pressure_plate_at(old_pos):
		player_ref.echo_left_pressure_plate(old_pos)
	
	if maze_ref.has_pressure_plate_at(new_pos):
		player_ref.echo_entered_pressure_plate(new_pos)

func _finish_echo():
	if state == State.FINISHED:
		return
	state = State.FINISHED
	print("Quantum Echo finished its path")
	if is_instance_valid(player_ref):
		player_ref._on_echo_finished()

func _grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position.x * cell_size + cell_size / 2, grid_position.y * cell_size + cell_size / 2)

func _world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x / cell_size), int(world_position.y / cell_size))

func cleanup():
	state = State.FINISHED # Prevent any pending logic from running
	if is_instance_valid(maze_ref) and maze_ref.has_pressure_plate_at(grid_pos):
		if is_instance_valid(player_ref):
			player_ref.echo_left_pressure_plate(grid_pos)
	queue_free()
