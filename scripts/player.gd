extends CharacterBody2D
class_name Player

@export var move_speed: float = 200.0
@export var cell_size: int = 32
@export var max_recording_time: float = 10.0
@export var grid_snap_threshold: float = 0.8

const QuantumEchoScene = preload("res://scenes/QuantumEcho.tscn")

var grid_pos: Vector2i = Vector2i(1, 1)
var is_moving: bool = false
var input_buffer: Vector2 = Vector2.ZERO
var last_grid_pos: Vector2i = Vector2i(1, 1)

var position_history: Array[Vector2i] = []
var timing_history: Array[float] = []
var current_position_start_time: float = 0.0
var remaining_recording_time: float = 0.0
var recording_start_time: float = 0.0
var is_recording: bool = false
var echo_active: bool = false
var quantum_echo: QuantumEcho = null

enum EchoState { READY, RECORDING, PLAYBACK_READY, PLAYING }
var echo_state: EchoState = EchoState.READY

var level_loader: LevelLoader
var player_plates: Array[Vector2i] = []
var echo_plates: Array[Vector2i] = []

var ui: CanvasLayer

func _ready():
	collision_layer = 2
	collision_mask = 1
	
	remaining_recording_time = max_recording_time
	
	level_loader = get_parent().get_node("LevelLoader")
	level_loader.level_generated.connect(reset_to_start)
	
	ui = get_tree().root.get_node("main/UI")
	
	_set_grid_position(Vector2i(1, 1))
	current_position_start_time = Time.get_unix_time_from_system()
	_check_plate_interaction()

func _physics_process(delta):
	_handle_input()
	_handle_movement(delta)
	_update_grid_position()
	_update_recording_time(delta)
	_check_for_tutorial_triggers()

func is_tutorial_level() -> bool:
	if is_instance_valid(level_loader) and level_loader.get_current_level_index() < level_loader.level_files.size():
		return level_loader.level_files[level_loader.get_current_level_index()].ends_with("tutorial.txt")
	return false

func _update_recording_time(delta):
	if is_recording:
		remaining_recording_time -= delta
		if remaining_recording_time <= 0:
			remaining_recording_time = 0
			_force_stop_recording()

func _handle_input():
	if Input.is_action_just_pressed("quantum_echo"):
		_handle_quantum_echo_button()
		# REMOVED: Tutorial trigger is no longer here.
		return
	
	if Input.is_action_just_pressed("ui_accept"):
		_interact()
		return
	
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_up"): input_dir.y -= 1
	if Input.is_action_pressed("move_down"): input_dir.y += 1
	if Input.is_action_pressed("move_left"): input_dir.x -= 1
	if Input.is_action_pressed("move_right"): input_dir.x += 1
	
	if input_dir.length() > 0 and is_tutorial_level():
		ui.show_tutorial("MOVE")
	
	input_buffer = input_dir.normalized()

func _check_for_tutorial_triggers():
	if not is_instance_valid(ui): return
	
	if not is_tutorial_level():
		ui.hide_all_tutorials()
		return
	
	var check_radius = 2
	var nearby_objects = {}
	
	for y in range(grid_pos.y - check_radius, grid_pos.y + check_radius + 1):
		for x in range(grid_pos.x - check_radius, grid_pos.x + check_radius + 1):
			var pos = Vector2i(x, y)
			if level_loader.switches.has(pos): nearby_objects["SWITCH"] = true
			if level_loader.doors.has(pos) and not level_loader.doors[pos]: nearby_objects["DOOR"] = true
			if level_loader.plates.has(pos): nearby_objects["PLATE"] = true
			if level_loader.gates.has(pos) and not level_loader.gates[pos]: nearby_objects["GATE"] = true
			if level_loader.reset_switches.has(pos): nearby_objects["RESET"] = true
			if is_instance_valid(level_loader.goal_instance) and level_loader.goal_instance.get_parent() and _world_to_grid(level_loader.goal_instance.position) == pos:
				nearby_objects["GOAL"] = true

	var tutorial_to_show = ""
	if "GOAL" in nearby_objects: tutorial_to_show = "GOAL"
	if "SWITCH" in nearby_objects: tutorial_to_show = "SWITCH"
	if "DOOR" in nearby_objects: tutorial_to_show = "DOOR"
	if "PLATE" in nearby_objects: tutorial_to_show = "PLATE"
	if "GATE" in nearby_objects: tutorial_to_show = "GATE"
	if "RESET" in nearby_objects: tutorial_to_show = "RESET"
	
	if tutorial_to_show != "":
		ui.show_tutorial(tutorial_to_show)
	
	var keys_to_hide = ["GOAL", "SWITCH", "DOOR", "PLATE", "GATE", "RESET"]
	for key in keys_to_hide:
		if not key in nearby_objects:
			ui.hide_tutorial(key)

func _handle_quantum_echo_button():
	match echo_state:
		EchoState.READY:
			if remaining_recording_time > 0: _start_recording()
			else: print("No recording time remaining!")
		EchoState.RECORDING: _stop_recording()
		EchoState.PLAYBACK_READY: _activate_echo()
		EchoState.PLAYING: _deactivate_echo()

func _handle_movement(delta):
	if input_buffer.length() > 0:
		velocity = input_buffer * move_speed
		is_moving = true
	else:
		velocity = Vector2.ZERO
		is_moving = false
	
	move_and_slide()
	
	if not is_moving:
		_snap_to_grid()

func _update_grid_position():
	var new_grid_pos = _world_to_grid(position)
	
	if new_grid_pos != last_grid_pos:
		_handle_position_change(last_grid_pos, new_grid_pos)
		
		if is_recording and not echo_active:
			var current_time = Time.get_unix_time_from_system()
			var time_spent = current_time - current_position_start_time
			_record_timing(time_spent)
			_add_to_history(new_grid_pos)
			current_position_start_time = current_time
		elif new_grid_pos != last_grid_pos:
			current_position_start_time = Time.get_unix_time_from_system()
		
		last_grid_pos = new_grid_pos
	
	grid_pos = new_grid_pos

func _snap_to_grid():
	var grid_center = _grid_to_world(grid_pos)
	if position.distance_to(grid_center) <= cell_size * grid_snap_threshold:
		position = grid_center

func _handle_position_change(old_pos: Vector2i, new_pos: Vector2i):
	if level_loader.has_pressure_plate_at(old_pos):
		_leave_pressure_plate(old_pos, true)
	if level_loader.has_pressure_plate_at(new_pos):
		_enter_pressure_plate(new_pos, true)

func _interact():
	for dir in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var pos_to_check = grid_pos + dir
		if level_loader.has_switch_at(pos_to_check):
			level_loader.toggle_switch(pos_to_check)
			return

func _start_recording():
	is_recording = true
	echo_state = EchoState.RECORDING
	recording_start_time = Time.get_unix_time_from_system()
	position_history.clear()
	timing_history.clear()
	_add_to_history(grid_pos)
	current_position_start_time = recording_start_time
	print("Recording started! Time remaining: ", "%.1f" % remaining_recording_time, "s")

func _stop_recording():
	if not is_recording: return
	is_recording = false
	var current_time = Time.get_unix_time_from_system()
	var time_spent_in_last_cell = current_time - current_position_start_time
	_record_timing(time_spent_in_last_cell)
	var recording_duration = current_time - recording_start_time
	
	if position_history.size() > 1:
		echo_state = EchoState.PLAYBACK_READY
		print("Recording stopped! Used ", "%.1f" % recording_duration, "s. Press quantum echo again to replay")
	else:
		echo_state = EchoState.READY
		remaining_recording_time += recording_duration
		remaining_recording_time = min(remaining_recording_time, max_recording_time)
		print("No movement recorded, time refunded")

func _force_stop_recording():
	if not is_recording: return
	is_recording = false
	var current_time = Time.get_unix_time_from_system()
	var time_spent_in_last_cell = current_time - current_position_start_time
	_record_timing(time_spent_in_last_cell)
	
	if position_history.size() > 1:
		echo_state = EchoState.PLAYBACK_READY
		print("Recording time exhausted! Press quantum echo to replay")
	else:
		echo_state = EchoState.READY
		print("Recording time exhausted with no movement recorded")

func _activate_echo():
	if position_history.size() == 0:
		echo_state = EchoState.READY
		return
	
	quantum_echo = QuantumEchoScene.instantiate()
	get_parent().add_child(quantum_echo)
	quantum_echo.setup(position_history, timing_history, self, level_loader, $Sprite2D)
	echo_active = true
	echo_state = EchoState.PLAYING
	print("Quantum Echo activated! Press quantum echo again to cancel")

func _deactivate_echo():
	if quantum_echo:
		quantum_echo.cleanup()
		quantum_echo = null
	
	echo_active = false
	echo_plates.clear()
	position_history.clear()
	timing_history.clear()
	echo_state = EchoState.READY
	print("Quantum Echo deactivated")

func _on_echo_finished():
	_deactivate_echo()

func echo_entered_pressure_plate(pos: Vector2i):
	if not echo_plates.has(pos):
		echo_plates.append(pos)
		level_loader.activate_pressure_plate(pos)

func echo_left_pressure_plate(pos: Vector2i):
	if echo_plates.has(pos):
		echo_plates.erase(pos)
		if not player_plates.has(pos):
			level_loader.deactivate_pressure_plate(pos)

func _enter_pressure_plate(pos: Vector2i, is_player: bool):
	var plates_array = player_plates if is_player else echo_plates
	if not plates_array.has(pos):
		plates_array.append(pos)
		level_loader.activate_pressure_plate(pos)

		# ADDED: Show echo tutorial when player steps on a plate for the first time
		if is_player and is_tutorial_level():
			ui.show_tutorial("ECHO")

func _leave_pressure_plate(pos: Vector2i, is_player: bool):
	var plates_array = player_plates if is_player else echo_plates
	var other_plates = echo_plates if is_player else player_plates
	if plates_array.has(pos):
		plates_array.erase(pos)
		if not other_plates.has(pos):
			level_loader.deactivate_pressure_plate(pos)

func _check_plate_interaction():
	if is_instance_valid(level_loader) and level_loader.has_pressure_plate_at(grid_pos):
		_enter_pressure_plate(grid_pos, true)

func _add_to_history(pos: Vector2i): position_history.append(pos)
func _record_timing(time_spent: float): timing_history.append(time_spent)
func _set_grid_position(new_pos: Vector2i):
	grid_pos = new_pos
	last_grid_pos = new_pos
	position = _grid_to_world(grid_pos)
func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * cell_size + cell_size / 2, grid_pos.y * cell_size + cell_size / 2)
func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / cell_size), int(world_pos.y / cell_size))

func reset_to_start(player_start_pos: Vector2i):
	print("Player resetting to start position.")
	for pos in player_plates:
		if is_instance_valid(level_loader):
			level_loader.deactivate_pressure_plate(pos)
	player_plates.clear()
	
	_deactivate_echo()
	is_recording = false
	echo_state = EchoState.READY
	remaining_recording_time = max_recording_time
	_set_grid_position(player_start_pos)
	position_history.clear()
	timing_history.clear()
	current_position_start_time = Time.get_unix_time_from_system()
	_check_plate_interaction()
	
	if is_instance_valid(ui):
		ui.on_level_generated(player_start_pos)

func get_recording_status() -> String:
	match echo_state:
		EchoState.READY: return "Ready to record (%.1fs remaining)" % remaining_recording_time
		EchoState.RECORDING: return "Recording... (%.1fs left)" % remaining_recording_time
		EchoState.PLAYBACK_READY: return "Ready to replay (%d positions)" % position_history.size()
		EchoState.PLAYING: return "Playing quantum echo"
	return "Unknown state"
