extends CharacterBody2D
class_name Player

@export var move_speed: float = 200.0
@export var grid_based_movement: bool = true
@export var cell_size: int = 32

# Quantum Echo properties
@export var max_echo_steps: int = 20  # Maximum number of steps to remember
@export var echo_alpha: float = 0.6
@export var echo_move_speed: float = 150.0  # Speed of the quantum echo

# Grid-based movement variables
var grid_position: Vector2i = Vector2i(1, 1)  # Start at maze entrance
var is_moving: bool = false
var target_position: Vector2

# Quantum Echo system
var position_history: Array[Vector2i] = []  # Store previous grid positions
var quantum_echo_active: bool = false
var quantum_echo: QuantumEcho = null

# Reference to maze generator and sprite
var maze_generator: MazeGenerator
@onready var player_sprite: Sprite2D = $Sprite2D

# Interactive elements tracking
var player_on_pressure_plates: Array[Vector2i] = []
var echo_on_pressure_plates: Array[Vector2i] = []

# Quantum Echo class - the ghostly duplicate
class QuantumEcho:
	var position: Vector2
	var grid_position: Vector2i
	var target_position: Vector2
	var is_moving: bool = false
	var path_to_follow: Array[Vector2i] = []
	var current_path_index: int = 0
	var move_speed: float
	var alpha: float
	var cell_size: int
	var echo_sprite: Sprite2D
	var parent_node: Node2D
	var maze_ref: MazeGenerator
	var player_ref: Player
	
	func _init(start_pos: Vector2i, path: Array[Vector2i], speed: float, echo_alpha: float, size: int, original_sprite: Sprite2D, parent: Node2D, maze: MazeGenerator, player: Player):
		grid_position = start_pos
		path_to_follow = path.duplicate()
		move_speed = speed
		alpha = echo_alpha
		cell_size = size
		parent_node = parent
		maze_ref = maze
		player_ref = player
		
		# Create echo sprite as copy of original
		echo_sprite = Sprite2D.new()
		echo_sprite.texture = original_sprite.texture
		echo_sprite.scale = original_sprite.scale
		echo_sprite.offset = original_sprite.offset
		echo_sprite.flip_h = original_sprite.flip_h
		echo_sprite.flip_v = original_sprite.flip_v
		
		# Add slight cyan tint to distinguish it and make transparent
		echo_sprite.modulate = Color(0.7, 1.0, 1.0, alpha)
		
		# Add to scene
		parent_node.add_child(echo_sprite)
		
		position = grid_to_world(grid_position)
		target_position = position
		echo_sprite.position = position
		
		# Check initial pressure plate
		check_pressure_plate_interaction()
		
		# Start moving to first position in path if available
		if path_to_follow.size() > 0:
			start_next_move()
	
	func update(delta: float):
		if is_moving:
			var old_grid_pos = grid_position
			
			# Move towards target position
			position = position.move_toward(target_position, move_speed * delta)
			echo_sprite.position = position
			
			# Check if we've reached the target
			if position.distance_to(target_position) < 1.0:
				position = target_position
				echo_sprite.position = position
				var new_grid_pos = Vector2i(int(target_position.x / cell_size), int(target_position.y / cell_size))
				
				# Handle position change
				if new_grid_pos != grid_position:
					handle_position_change(old_grid_pos, new_grid_pos)
				
				grid_position = new_grid_pos
				is_moving = false
				
				# Move to next position in path
				current_path_index += 1
				start_next_move()
	
	func handle_position_change(old_pos: Vector2i, new_pos: Vector2i):
		# Handle leaving pressure plates
		if maze_ref.is_pressure_plate_at(old_pos):
			player_ref.echo_left_pressure_plate(old_pos)
		
		# Handle entering pressure plates
		if maze_ref.is_pressure_plate_at(new_pos):
			player_ref.echo_entered_pressure_plate(new_pos)
	
	func start_next_move():
		if current_path_index < path_to_follow.size():
			var next_grid_pos = path_to_follow[current_path_index]
			target_position = grid_to_world(next_grid_pos)
			is_moving = true
		# If we've reached the end of the path, the echo just stops
	
	func check_pressure_plate_interaction():
		if maze_ref.is_pressure_plate_at(grid_position):
			player_ref.echo_entered_pressure_plate(grid_position)
	
	func grid_to_world(grid_pos: Vector2i) -> Vector2:
		return Vector2(
			grid_pos.x * cell_size + cell_size / 2,
			grid_pos.y * cell_size + cell_size / 2
		)
	
	func is_finished() -> bool:
		return current_path_index >= path_to_follow.size() and not is_moving
	
	func cleanup():
		# Handle leaving any pressure plates the echo was on
		if maze_ref.is_pressure_plate_at(grid_position):
			player_ref.echo_left_pressure_plate(grid_position)
		
		if echo_sprite != null:
			echo_sprite.queue_free()

func _ready():
	# Find the maze generator in the scene
	maze_generator = get_parent().get_node("MazeGenerator") as MazeGenerator
	
	if maze_generator == null:
		push_error("Player could not find MazeGenerator node!")
		return
	
	# Set initial position
	set_grid_position(Vector2i(1, 1))
	# Add initial position to history
	add_position_to_history(grid_position)
	
	# Check initial pressure plate interaction
	check_pressure_plate_interaction()

func _physics_process(delta):
	# Update quantum echo if active
	if quantum_echo_active and quantum_echo != null:
		quantum_echo.update(delta)
		
		# Check if echo has finished its path
		if quantum_echo.is_finished():
			deactivate_quantum_echo()
	
	# Handle normal player movement
	if grid_based_movement:
		handle_grid_movement(delta)
	else:
		handle_smooth_movement(delta)

func handle_grid_movement(delta):
	if is_moving:
		# Move towards target position
		position = position.move_toward(target_position, move_speed * delta)
		
		# Check if we've reached the target
		if position.distance_to(target_position) < 1.0:
			position = target_position
			is_moving = false
	else:
		# Check for input
		var input_direction = get_input_direction()
		if input_direction != Vector2i.ZERO:
			try_move(input_direction)

func handle_smooth_movement(delta):
	var input_direction = get_input_direction_smooth()
	
	if input_direction != Vector2.ZERO:
		# Calculate desired velocity
		var desired_velocity = input_direction * move_speed
		
		# Check collision for the next position
		var next_position = position + desired_velocity * delta
		
		# Check collision more precisely by testing the player's bounds
		var player_radius = cell_size * 0.4  # Assuming player takes up most of the cell
		
		# Check multiple points around the player's future position
		var collision_points = [
			next_position + Vector2(player_radius, 0),      # Right
			next_position + Vector2(-player_radius, 0),     # Left
			next_position + Vector2(0, player_radius),      # Down
			next_position + Vector2(0, -player_radius),     # Up
			next_position + Vector2(player_radius, player_radius),    # Bottom-right
			next_position + Vector2(-player_radius, player_radius),   # Bottom-left
			next_position + Vector2(player_radius, -player_radius),   # Top-right
			next_position + Vector2(-player_radius, -player_radius),  # Top-left
			next_position  # Center
		]
		
		var can_move_x = true
		var can_move_y = true
		
		# Check horizontal movement
		var horizontal_pos = position + Vector2(desired_velocity.x * delta, 0)
		var h_points = [
			horizontal_pos + Vector2(player_radius if desired_velocity.x > 0 else -player_radius, player_radius),
			horizontal_pos + Vector2(player_radius if desired_velocity.x > 0 else -player_radius, -player_radius),
			horizontal_pos + Vector2(player_radius if desired_velocity.x > 0 else -player_radius, 0)
		]
		
		for point in h_points:
			var grid_pos = world_to_grid(point)
			if not can_move_to(grid_pos):
				can_move_x = false
				break
		
		# Check vertical movement
		var vertical_pos = position + Vector2(0, desired_velocity.y * delta)
		var v_points = [
			vertical_pos + Vector2(player_radius, player_radius if desired_velocity.y > 0 else -player_radius),
			vertical_pos + Vector2(-player_radius, player_radius if desired_velocity.y > 0 else -player_radius),
			vertical_pos + Vector2(0, player_radius if desired_velocity.y > 0 else -player_radius)
		]
		
		for point in v_points:
			var grid_pos = world_to_grid(point)
			if not can_move_to(grid_pos):
				can_move_y = false
				break
		
		# Apply velocity based on collision results
		velocity = Vector2(
			desired_velocity.x if can_move_x else 0,
			desired_velocity.y if can_move_y else 0
		)
		
		# Update grid position for pressure plate interactions
		var new_grid_pos = world_to_grid(position)
		if new_grid_pos != grid_position:
			handle_position_change(grid_position, new_grid_pos)
			grid_position = new_grid_pos
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

func get_input_direction() -> Vector2i:
	# Check for quantum echo activation first
	if Input.is_action_just_pressed("quantum_echo"):
		toggle_quantum_echo()
		return Vector2i.ZERO
	
	# Check for interaction
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact"):
		interact_with_environment()
		return Vector2i.ZERO
	
	# Grid-based input (one move per press)
	if Input.is_action_just_pressed("move_up"):
		return Vector2i(0, -1)
	elif Input.is_action_just_pressed("move_down"):
		return Vector2i(0, 1)
	elif Input.is_action_just_pressed("move_left"):
		return Vector2i(-1, 0)
	elif Input.is_action_just_pressed("move_right"):
		return Vector2i(1, 0)
	
	return Vector2i.ZERO

func get_input_direction_smooth() -> Vector2:
	# Check for quantum echo activation first
	if Input.is_action_just_pressed("quantum_echo"):
		toggle_quantum_echo()
		return Vector2.ZERO
	
	# Check for interaction
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact"):
		interact_with_environment()
		return Vector2.ZERO
	
	# Smooth movement input
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	
	return direction.normalized()

func interact_with_environment():
	"""Handle interactions with switches and other objects"""
	# Check adjacent cells for switches
	var adjacent_positions = [
		grid_position + Vector2i(0, -1),  # North
		grid_position + Vector2i(1, 0),   # East
		grid_position + Vector2i(0, 1),   # South
		grid_position + Vector2i(-1, 0),  # West
		grid_position  # Current position
	]
	
	for pos in adjacent_positions:
		if maze_generator.is_switch_at(pos):
			var state = maze_generator.toggle_switch(pos)
			print("Switch at ", pos, " toggled to: ", state)
			return  # Only interact with one switch per press

func try_move(direction: Vector2i):
	var new_grid_pos = grid_position + direction
	
	if can_move_to(new_grid_pos):
		move_to_grid_position(new_grid_pos)

func can_move_to(grid_pos: Vector2i) -> bool:
	if maze_generator == null:
		return false
	
	return maze_generator.is_path_at(grid_pos.x, grid_pos.y)

func move_to_grid_position(new_pos: Vector2i):
	var old_pos = grid_position
	grid_position = new_pos
	target_position = grid_to_world(grid_position)
	is_moving = true
	
	# Handle leaving old position
	handle_position_change(old_pos, new_pos)
	
	# Add new position to history (only if quantum echo is not active)
	# When echo is active, we want to preserve the original path
	if not quantum_echo_active:
		add_position_to_history(grid_position)

func handle_position_change(old_pos: Vector2i, new_pos: Vector2i):
	"""Handle interactions when moving between positions"""
	# Handle leaving pressure plates
	if maze_generator.is_pressure_plate_at(old_pos):
		player_left_pressure_plate(old_pos)
	
	# Handle entering pressure plates
	if maze_generator.is_pressure_plate_at(new_pos):
		player_entered_pressure_plate(new_pos)

func check_pressure_plate_interaction():
	"""Check if player is on a pressure plate at current position"""
	if maze_generator.is_pressure_plate_at(grid_position):
		player_entered_pressure_plate(grid_position)

func player_entered_pressure_plate(pos: Vector2i):
	"""Handle player entering a pressure plate"""
	if not player_on_pressure_plates.has(pos):
		player_on_pressure_plates.append(pos)
		maze_generator.activate_pressure_plate(pos)
		print("Player activated pressure plate at ", pos)

func player_left_pressure_plate(pos: Vector2i):
	"""Handle player leaving a pressure plate"""
	if player_on_pressure_plates.has(pos):
		player_on_pressure_plates.erase(pos)
		# Only deactivate if echo is not also on this plate
		if not echo_on_pressure_plates.has(pos):
			maze_generator.deactivate_pressure_plate(pos)
			print("Player deactivated pressure plate at ", pos)

func echo_entered_pressure_plate(pos: Vector2i):
	"""Handle quantum echo entering a pressure plate"""
	if not echo_on_pressure_plates.has(pos):
		echo_on_pressure_plates.append(pos)
		maze_generator.activate_pressure_plate(pos)
		print("Quantum Echo activated pressure plate at ", pos)

func echo_left_pressure_plate(pos: Vector2i):
	"""Handle quantum echo leaving a pressure plate"""
	if echo_on_pressure_plates.has(pos):
		echo_on_pressure_plates.erase(pos)
		# Only deactivate if player is not also on this plate
		if not player_on_pressure_plates.has(pos):
			maze_generator.deactivate_pressure_plate(pos)
			print("Quantum Echo deactivated pressure plate at ", pos)

func set_grid_position(new_pos: Vector2i):
	grid_position = new_pos
	position = grid_to_world(grid_position)
	target_position = position

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * cell_size + cell_size / 2,
		grid_pos.y * cell_size + cell_size / 2
	)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / cell_size),
		int(world_pos.y / cell_size)
	)

func get_grid_position() -> Vector2i:
	return grid_position

# Utility function to reset player position
func reset_to_start():
	# Clean up pressure plate states
	for pos in player_on_pressure_plates:
		maze_generator.deactivate_pressure_plate(pos)
	player_on_pressure_plates.clear()
	
	set_grid_position(Vector2i(1, 1))
	position_history.clear()
	add_position_to_history(grid_position)
	deactivate_quantum_echo()
	
	# Check initial pressure plate interaction
	check_pressure_plate_interaction()

# Quantum Echo System Functions

func add_position_to_history(pos: Vector2i):
	"""Add a position to the movement history"""
	# Only add if it's different from the last position
	if position_history.is_empty() or position_history[-1] != pos:
		position_history.append(pos)
		
		# Keep history within max limit
		if position_history.size() > max_echo_steps:
			position_history.pop_front()

func toggle_quantum_echo():
	"""Toggle the quantum echo on/off"""
	if quantum_echo_active:
		deactivate_quantum_echo()
	else:
		activate_quantum_echo()

func activate_quantum_echo():
	"""Create and activate the quantum echo"""
	if position_history.size() <= 1:
		print("Not enough movement history for Quantum Echo")
		return
	
	if player_sprite == null:
		print("Player sprite not found!")
		return
	
	# Create the path for the echo (exclude current position)
	var echo_path = position_history.slice(1, position_history.size())  # Skip starting position
	
	# Create the quantum echo starting from the beginning of our path
	quantum_echo = QuantumEcho.new(
		position_history[0],  # Start from first recorded position
		echo_path,
		echo_move_speed,
		echo_alpha,
		cell_size,
		player_sprite,
		get_parent(),  # Add echo sprite to same parent as player
		maze_generator,
		self
	)
	
	quantum_echo_active = true
	
	# Clear current history and start fresh path for player
	var current_pos = grid_position
	position_history.clear()
	add_position_to_history(current_pos)
	
	print("Quantum Echo activated! Echo will follow ", echo_path.size(), " positions")

func deactivate_quantum_echo():
	"""Deactivate the quantum echo"""
	if quantum_echo != null:
		quantum_echo.cleanup()  # Clean up the sprite and pressure plates
	
	# Clean up echo pressure plate states
	echo_on_pressure_plates.clear()
	
	quantum_echo_active = false
	quantum_echo = null
	print("Quantum Echo deactivated")

func get_position_history() -> Array[Vector2i]:
	"""Get the current position history"""
	return position_history.duplicate()

func get_quantum_echo_position() -> Vector2:
	"""Get the current position of the quantum echo (useful for external systems)"""
	if quantum_echo != null:
		return quantum_echo.position
	return Vector2.ZERO

func is_quantum_echo_active() -> bool:
	return quantum_echo_active

func _draw():
	"""Draw trail effects (quantum echo now uses actual sprite)"""
	
	# Draw current path history as a faint trail
	if position_history.size() > 1:
		for i in range(position_history.size() - 1):
			var trail_pos = position_history[i]
			var world_pos = grid_to_world(trail_pos)
			var local_pos = to_local(world_pos)
			
			# Calculate alpha based on age
			var age_factor = float(i) / float(position_history.size() - 1)
			var alpha = 0.1 + 0.2 * age_factor
			
			var trail_color = Color.WHITE
			trail_color.a = alpha
			
			# Draw small trail dots
			var radius = cell_size * 0.1
			draw_circle(local_pos, radius, trail_color)
	
	# Draw echo's future path if active
	if quantum_echo_active and quantum_echo != null:
		if quantum_echo.current_path_index < quantum_echo.path_to_follow.size():
			for i in range(quantum_echo.current_path_index, min(quantum_echo.current_path_index + 5, quantum_echo.path_to_follow.size())):
				var future_pos = grid_to_world(quantum_echo.path_to_follow[i])
				var local_pos = to_local(future_pos)
				
				var future_alpha = echo_alpha * 0.3 * (1.0 - float(i - quantum_echo.current_path_index) / 5.0)
				var future_color = Color.CYAN
				future_color.a = future_alpha
				
				draw_circle(local_pos, cell_size * 0.15, future_color)

func _process(_delta):
	# Trigger redraw for visual effects
	queue_redraw()

# Debug functions
func print_game_state():
	print("=== GAME STATE ===")
	print("Player position: ", grid_position)
	print("Player on pressure plates: ", player_on_pressure_plates)
	print("Echo on pressure plates: ", echo_on_pressure_plates)
	print("Echo active: ", quantum_echo_active)
	if quantum_echo != null:
		print("Echo position: ", quantum_echo.grid_position)
	print("Position history size: ", position_history.size())
