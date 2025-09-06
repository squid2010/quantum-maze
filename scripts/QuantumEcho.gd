extends Sprite2D
class_name QuantumEcho

@export var cell_size: int = 32

var path: Array[Vector2i] = []
var timings: Array[float] = []
var current_target_index: int = 0
var grid_pos: Vector2i
var last_grid_pos: Vector2i
var target_world_pos: Vector2
var is_moving: bool = false
var movement_timer: float = 0.0
var current_movement_time: float = 0.0
var start_world_pos: Vector2

var player_ref: Player
var maze_ref: MazeGenerator

func setup(start_pos: Vector2i, echo_path: Array[Vector2i], echo_timings: Array[float], player: Player, maze: MazeGenerator, original_sprite: Sprite2D):
	grid_pos = start_pos
	last_grid_pos = start_pos
	path = echo_path.duplicate()
	timings = echo_timings.duplicate()
	player_ref = player
	maze_ref = maze
	
	# Copy sprite properties
	texture = original_sprite.texture
	scale = original_sprite.get_parent().scale
	modulate = Color(0.7, 1.0, 1.0, 0.6)
	
	position = _grid_to_world(grid_pos)
	
	# Start moving to first target
	_start_next_movement()

func _ready():
	# Check initial pressure plate
	if maze_ref and maze_ref.has_pressure_plate_at(grid_pos):
		player_ref.echo_entered_pressure_plate(grid_pos)

func _process(delta):
	if is_moving and current_target_index < path.size():
		movement_timer += delta
		
		# Calculate progress (0 to 1)
		var progress = movement_timer / current_movement_time
		progress = clamp(progress, 0.0, 1.0)
		
		# Smooth interpolation to target
		position = start_world_pos.lerp(target_world_pos, _ease_in_out(progress))
		
		# Update grid position and check for changes
		var new_grid_pos = _world_to_grid(position)
		if new_grid_pos != last_grid_pos:
			_handle_position_change(last_grid_pos, new_grid_pos)
			last_grid_pos = new_grid_pos
		
		# Check if movement is complete
		if progress >= 1.0:
			position = target_world_pos
			grid_pos = path[current_target_index]
			last_grid_pos = grid_pos
			is_moving = false
			
			# Handle final position change for this movement
			_handle_position_change(_world_to_grid(start_world_pos), grid_pos)
			
			current_target_index += 1
			_start_next_movement()
	elif not is_moving and current_target_index >= path.size():
		# Echo has completed its path
		_finish_echo()

func _start_next_movement():
	if current_target_index < path.size():
		# Set up next movement
		start_world_pos = position
		target_world_pos = _grid_to_world(path[current_target_index])
		current_movement_time = timings[current_target_index] if current_target_index < timings.size() else 1.0
		
		# Minimum movement time to prevent division by zero and too-fast movement
		current_movement_time = max(current_movement_time, 0.1)
		
		movement_timer = 0.0
		is_moving = true
		
		print("Echo moving to ", path[current_target_index], " over ", current_movement_time, " seconds")

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
	"""Called when the echo has completed its path"""
	print("Quantum Echo finished its path")
	player_ref._on_echo_finished()

func _grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position.x * cell_size + cell_size / 2, grid_position.y * cell_size + cell_size / 2)

func _world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(int(round(world_position.x / cell_size)), int(round(world_position.y / cell_size)))

func is_finished() -> bool:
	return current_target_index >= path.size() and not is_moving

func cleanup():
	if maze_ref and maze_ref.has_pressure_plate_at(grid_pos):
		player_ref.echo_left_pressure_plate(grid_pos)
	queue_free()
