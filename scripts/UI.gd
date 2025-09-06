extends CanvasLayer

# References to the UI nodes
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var time_bar: ProgressBar = $MarginContainer/VBoxContainer/TimeBar

# --- UPDATED PATHS ---
# References to the game nodes
@onready var player: Player = get_tree().root.get_node("main/World/Player")
@onready var maze_generator: MazeGenerator = get_tree().root.get_node("main/World/MazeGenerator")
# ---------------------

func _process(delta: float) -> void:
	# Ensure player and maze are ready before updating
	if not is_instance_valid(player) or not is_instance_valid(maze_generator):
		return

	# Update the UI elements every frame
	update_level_label()
	update_status_label()
	update_time_bar()

func update_level_label() -> void:
	# Get the current level index from the maze generator and add 1 for display
	level_label.text = "Level: %d" % (maze_generator.get_current_level_index() + 1)

func update_status_label() -> void:
	# Use the existing get_recording_status() function from the player
	status_label.text = player.get_recording_status()

func update_time_bar() -> void:
	# Set the max value and current value of the progress bar
	time_bar.max_value = player.max_recording_time
	time_bar.value = player.remaining_recording_time
