extends CharacterBody2D
class_name Player

@export var move_speed: float = 200.0
@export var cell_size: int = 32
@export var max_recording_time: float = 10.0  # Total recording budget in seconds
@export var grid_snap_threshold: float = 0.8  # How close to grid center before snapping

# Preload the QuantumEcho scene
const QuantumEchoScene = preload("res://scenes/QuantumEcho.tscn")

# Current state
var grid_pos: Vector2i = Vector2i(1, 1)
var is_moving: bool = false
var movement_direction: Vector2 = Vector2.ZERO
var input_buffer: Vector2 = Vector2.ZERO
var last_grid_pos: Vector2i = Vector2i(1, 1)

# Quantum Echo system - time-based recording
var position_history: Array[Vector2i] = []
var timing_history: Array[float] = []
var current_position_start_time: float = 0.0
var remaining_recording_time: float = 0.0  # How much recording time is left
var recording_start_time: float = 0.0
var is_recording: bool = false
var echo_active: bool = false
var quantum_echo: QuantumEcho = null

# State tracking for the single button
enum EchoState { READY, RECORDING, PLAYBACK_READY, PLAYING }
var echo_state: EchoState = EchoState.READY

# References
var maze: MazeGenerator
var player_plates: Array[Vector2i] = []
var echo_plates: Array[Vector2i] = []

func _ready():
	# Set up collision layers
	collision_layer = 2  # Player is on layer 2
	collision_mask = 1   # Player collides with layer 1 (walls, doors, gates)
	
	remaining_recording_time = max_recording_time
	
	maze = get_parent().get_node("MazeGenerator")
	maze.level_generated.connect(reset_to_start) # Connect to the signal
	
	_set_grid_position(Vector2i(1, 1))
	current_position_start_time = Time.get_unix_time_from_system()
	_check_plate_interaction()

func _physics_process(delta):
	_handle_input()
	_handle_movement(delta)
	_update_grid_position()
	_update_recording_time(delta)

func _update_recording_time(delta):
	if is_recording:
		remaining_recording_time -= delta
		if remaining_recording_time <= 0:
			remaining_recording_time = 0
			_force_stop_recording()

func _handle_input():
	# Single quantum echo button handles all states
	if Input.is_action_just_pressed("quantum_echo"):
		_handle_quantum_echo_button()
		return
	
	# Interaction
	if Input.is_action_just_pressed("ui_accept"):
		_interact()
		return
	
	# Get movement input
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	
	# Normalize diagonal movement
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	
	input_buffer = input_dir

func _handle_quantum_echo_button():
	match echo_state:
		EchoState.READY:
			if remaining_recording_time > 0:
				_start_recording()
			else:
				print("No recording time remaining!")
		
		EchoState.RECORDING:
			_stop_recording()
		
		EchoState.PLAYBACK_READY:
			_activate_echo()
		
		EchoState.PLAYING:
			_deactivate_echo()

func _handle_movement(delta):
	var desired_velocity = Vector2.ZERO
	
	if input_buffer.length() > 0:
		desired_velocity = input_buffer * move_speed
		is_moving = true
	else:
		is_moving = false
	
	# Always apply velocity and let Godot's collision system handle walls
	velocity = desired_velocity
	move_and_slide()
	
	# Auto-snap to grid when not moving
	if not is_moving:
		_snap_to_grid()

func _update_grid_position():
	var new_grid_pos = _world_to_grid(position)
	
	# Check if we've moved to a new grid cell
	if new_grid_pos != last_grid_pos:
		_handle_position_change(last_grid_pos, new_grid_pos)
		
		# Record timing and add to history only when recording
		if is_recording and not echo_active:
			var current_time = Time.get_unix_time_from_system()
			var time_spent = current_time - current_position_start_time
			_record_timing(time_spent)
			_add_to_history(new_grid_pos)
			current_position_start_time = current_time
		elif not is_recording and new_grid_pos != last_grid_pos:
			# Still update timing for non-recording movement
			current_position_start_time = Time.get_unix_time_from_system()
		
		last_grid_pos = new_grid_pos
	
	grid_pos = new_grid_pos

func _snap_to_grid():
	var grid_center = _grid_to_world(grid_pos)
	var distance_to_center = position.distance_to(grid_center)
	
	# Snap to grid center if close enough
	if distance_to_center <= cell_size * grid_snap_threshold:
		position = grid_center

func _handle_position_change(old_pos: Vector2i, new_pos: Vector2i):
	# Handle pressure plates
	if maze.has_pressure_plate_at(old_pos):
		_leave_pressure_plate(old_pos, true)
	
	if maze.has_pressure_plate_at(new_pos):
		_enter_pressure_plate(new_pos, true)

func _interact():
	# Check adjacent cells for switches
	var adjacent = [
		grid_pos + Vector2i(0, -1), grid_pos + Vector2i(1, 0),
		grid_pos + Vector2i(0, 1), grid_pos + Vector2i(-1, 0), grid_pos
	]
	
	for pos in adjacent:
		if maze.has_switch_at(pos):
			maze.toggle_switch(pos)
			return

func _start_recording():
	is_recording = true
	echo_state = EchoState.RECORDING
	recording_start_time = Time.get_unix_time_from_system()
	
	position_history.clear()
	timing_history.clear()
	
	# Add current position as starting point
	_add_to_history(grid_pos)
	current_position_start_time = recording_start_time
	
	print("Recording started! Time remaining: ", "%.1f" % remaining_recording_time, "s")

func _stop_recording():
	if not is_recording:
		return
	
	is_recording = false
	
	# Record the time spent in the final position
	var current_time = Time.get_unix_time_from_system()
	var time_spent_in_last_cell = current_time - current_position_start_time
	_record_timing(time_spent_in_last_cell)
	
	var recording_duration = current_time - recording_start_time
	
	if position_history.size() > 0:
		echo_state = EchoState.PLAYBACK_READY
		print("Recording stopped! Used ", "%.1f" % recording_duration, "s")
		print("Remaining time: ", "%.1f" % remaining_recording_time, "s")
		print("Press quantum echo again to replay")
	else:
		echo_state = EchoState.READY
		# Refund unused time since no meaningful recording was made
		remaining_recording_time += recording_duration
		if remaining_recording_time > max_recording_time:
			remaining_recording_time = max_recording_time
		print("No movement recorded, time refunded")

func _force_stop_recording():
	"""Called when recording time runs out"""
	if not is_recording:
		return
	
	is_recording = false
	
	# Record the time spent in the final position
	var current_time = Time.get_unix_time_from_system()
	var time_spent_in_last_cell = current_time - current_position_start_time
	_record_timing(time_spent_in_last_cell)
	
	if position_history.size() > 0:
		echo_state = EchoState.PLAYBACK_READY
		print("Recording time exhausted! Press quantum echo to replay")
	else:
		echo_state = EchoState.READY
		print("Recording time exhausted with no movement recorded")

func _activate_echo():
	if position_history.size() == 0:
		print("No recorded sequence available!")
		echo_state = EchoState.READY
		return
	
	# Create quantum echo instance
	quantum_echo = QuantumEchoScene.instantiate()
	get_parent().add_child(quantum_echo)
	
	# Set up echo with recorded data.
	quantum_echo.setup(position_history, timing_history, self, maze, $Sprite2D)
	
	echo_active = true
	echo_state = EchoState.PLAYING
	print("Quantum Echo activated! Press quantum echo again to cancel")

func _deactivate_echo():
	if quantum_echo:
		quantum_echo.cleanup()
		quantum_echo = null
	
	echo_active = false
	echo_plates.clear()
	
	# Clear the recorded sequence after playback
	position_history.clear()
	timing_history.clear()
	echo_state = EchoState.READY
	
	print("Quantum Echo deactivated")

func _on_echo_finished():
	"""Called by QuantumEcho when it finishes its path"""
	_deactivate_echo()

# Pressure plate functions (called by QuantumEcho)
func echo_entered_pressure_plate(pos: Vector2i):
	if not echo_plates.has(pos):
		echo_plates.append(pos)
		maze.activate_pressure_plate(pos)

func echo_left_pressure_plate(pos: Vector2i):
	if echo_plates.has(pos):
		echo_plates.erase(pos)
		# Only deactivate if player isn't also on this plate
		if not player_plates.has(pos):
			maze.deactivate_pressure_plate(pos)

func _enter_pressure_plate(pos: Vector2i, is_player: bool):
	var plates_array = player_plates if is_player else echo_plates
	if not plates_array.has(pos):
		plates_array.append(pos)
		maze.activate_pressure_plate(pos)

func _leave_pressure_plate(pos: Vector2i, is_player: bool):
	var plates_array = player_plates if is_player else echo_plates
	var other_plates = echo_plates if is_player else player_plates
	
	if plates_array.has(pos):
		plates_array.erase(pos)
		# Only deactivate if other entity isn't on this plate
		if not other_plates.has(pos):
			maze.deactivate_pressure_plate(pos)

func _check_plate_interaction():
	if maze.has_pressure_plate_at(grid_pos):
		_enter_pressure_plate(grid_pos, true)

func _add_to_history(pos: Vector2i):
	position_history.append(pos)

func _record_timing(time_spent: float):
	timing_history.append(time_spent)

func _set_grid_position(new_pos: Vector2i):
	grid_pos = new_pos
	last_grid_pos = new_pos
	position = _grid_to_world(grid_pos)

func _grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position.x * cell_size + cell_size / 2, grid_position.y * cell_size + cell_size / 2)

func _world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x / cell_size), int(world_position.y / cell_size))

func _can_move_to_world_position(world_pos: Vector2) -> bool:
	var grid_pos_to_check = _world_to_grid(world_pos)
	return maze.is_path_at(grid_pos_to_check)

# Debug/utility
func reset_to_start():
	print("Player resetting to start position.")
	# Deactivate any active plates from the previous level
	for pos in player_plates:
		if is_instance_valid(maze):
			maze.deactivate_pressure_plate(pos)
	player_plates.clear()
	
	_deactivate_echo()
	is_recording = false
	echo_state = EchoState.READY
	remaining_recording_time = max_recording_time
	_set_grid_position(Vector2i(1, 1))
	position_history.clear()
	timing_history.clear()
	current_position_start_time = Time.get_unix_time_from_system()
	if is_instance_valid(maze):
		_check_plate_interaction()

# Status functions for UI/debugging
func get_recording_status() -> String:
	match echo_state:
		EchoState.READY:
			return "Ready to record (%.1fs remaining)" % remaining_recording_time
		EchoState.RECORDING:
			return "Recording... (%.1fs left)" % remaining_recording_time
		EchoState.PLAYBACK_READY:
			return "Ready to replay (%d positions)" % position_history.size()
		EchoState.PLAYING:
			return "Playing quantum echo"
	return "Unknown state"
