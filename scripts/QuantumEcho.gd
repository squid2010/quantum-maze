extends AnimatedSprite2D
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
var last_move_dir: Vector2 = Vector2.DOWN

var timer: float = 0.0
var current_duration: float = 0.0

var player_ref: Player
var loader_ref: LevelLoader
@onready var playback_sound: AudioStreamPlayer = $PlaybackSound

func setup(echo_path: Array[Vector2i], echo_timings: Array[float], player: Player, loader: LevelLoader, original_sprite: AnimatedSprite2D):
	if echo_path.is_empty():
		_finish_echo()
		return

	path = echo_path.duplicate()
	timings = echo_timings.duplicate()
	player_ref = player
	loader_ref = loader
	
	# Copy animations and appearance from the player's sprite
	self.sprite_frames = original_sprite.sprite_frames
	scale = original_sprite.get_parent().scale
	modulate = Color(0.7, 1.0, 1.0, 0.6)
	
	current_path_index = 0
	grid_pos = path[0]
	last_grid_pos = grid_pos
	position = _grid_to_world(grid_pos)
	
	playback_sound.play()
	_start_pause()

func _ready():
	if is_instance_valid(loader_ref) and loader_ref.has_pressure_plate_at(grid_pos):
		player_ref.echo_entered_pressure_plate(grid_pos)

func _process(delta):
	if state == State.FINISHED: return
	timer += delta
	
	if state == State.PAUSED:
		if timer >= current_duration:
			_start_move()

	elif state == State.MOVING:
		var progress = clamp(timer / current_duration if current_duration > 0 else 1.0, 0.0, 1.0)
		position = start_world_pos.lerp(target_world_pos, _ease_in_out(progress))
		
		var new_grid_pos = _world_to_grid(position)
		if new_grid_pos != last_grid_pos:
			_handle_position_change(last_grid_pos, new_grid_pos)
			last_grid_pos = new_grid_pos
		
		if progress >= 1.0:
			position = target_world_pos
			grid_pos = path[current_path_index]
			last_grid_pos = grid_pos
			_handle_position_change(_world_to_grid(start_world_pos), grid_pos)
			_start_pause()

func _update_animation():
	var animation_name = "idle"
	var direction_name = "down"

	if last_move_dir.x > 0:
		direction_name = "right"
	elif last_move_dir.x < 0:
		direction_name = "left"
	elif last_move_dir.y > 0:
		direction_name = "down"
	elif last_move_dir.y < 0:
		direction_name = "up"
	
	if state == State.MOVING:
		animation_name = "walk"
	
	self.play(animation_name + "_" + direction_name)

func _start_pause():
	timer = 0.0
	state = State.PAUSED
	_update_animation()
	
	if current_path_index < timings.size():
		current_duration = timings[current_path_index]
	else:
		current_duration = 0.1
		var final_timer = get_tree().create_timer(current_duration)
		await final_timer.timeout
		if state != State.FINISHED: _finish_echo()

func _start_move():
	current_path_index += 1
	if current_path_index >= path.size():
		_finish_echo()
		return
		
	timer = 0.0
	state = State.MOVING
	current_duration = 0.2
	start_world_pos = position
	target_world_pos = _grid_to_world(path[current_path_index])
	
	var move_dir = (target_world_pos - start_world_pos).normalized()
	if move_dir.length_squared() > 0:
		last_move_dir = move_dir
	
	_update_animation()

func _ease_in_out(t: float) -> float: return t * t * (3.0 - 2.0 * t)

func _handle_position_change(old_pos: Vector2i, new_pos: Vector2i):
	if old_pos == new_pos or not is_instance_valid(loader_ref): return
	if loader_ref.has_pressure_plate_at(old_pos): player_ref.echo_left_pressure_plate(old_pos)
	if loader_ref.has_pressure_plate_at(new_pos): player_ref.echo_entered_pressure_plate(new_pos)

func _finish_echo():
	if state == State.FINISHED: return
	state = State.FINISHED
	if is_instance_valid(player_ref): player_ref._on_echo_finished()

func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * cell_size + cell_size / 2, grid_pos.y * cell_size + cell_size / 2)
func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / cell_size), int(world_pos.y / cell_size))

func cleanup():
	state = State.FINISHED
	if is_instance_valid(playback_sound):
		playback_sound.stop()
	if is_instance_valid(loader_ref) and loader_ref.has_pressure_plate_at(grid_pos):
		if is_instance_valid(player_ref): player_ref.echo_left_pressure_plate(grid_pos)
	queue_free()
