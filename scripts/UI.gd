extends CanvasLayer

@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var time_bar: ProgressBar = $MarginContainer/VBoxContainer/TimeBar
@onready var tutorial_panel: Panel = $TutorialPanel
@onready var tutorial_label: RichTextLabel = $TutorialPanel/TutorialLabel

@onready var player: Player = get_tree().root.get_node("main/World/Player")
@onready var level_loader: LevelLoader = get_tree().root.get_node("main/World/LevelLoader")

var tutorial_messages = {
	"MOVE": "Use the [b]Arrow Keys[/b] to move your character.",
	"GOAL": "The [color=lightgreen]Goal[/color] is your objective. Reach it to proceed to the next level.",
	"SWITCH": "This is a [color=yellow]Switch[/color]. Interact with it using [b]Enter[/b] or [b]Spacebar[/b].",
	"DOOR": "This is a [color=red]Door[/color]. It can be opened by a switch.",
	"PLATE": "This is a [color=lightblue]Pressure Plate[/color]. It activates something while you or your echo stand on it.",
	"GATE": "This is a [color=purple]Gate[/color]. It stays open only while its pressure plate is held down.",
	"ECHO": "You need to hold the plate down. Try recording an [b]Echo[/b]! Press [b]Q[/b] to start/stop recording, and [b]Q[/b] again to play it back.",
	"RESET": "A [color=cyan]Reset Switch[/color] will turn off all other switches in the level."
}
var shown_tutorials: Array[String] = []
var current_tutorial_key: String = ""

func _ready():
	tutorial_panel.hide()
	if is_instance_valid(level_loader):
		level_loader.level_generated.connect(on_level_generated)

func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(level_loader):
		return

	update_level_label()
	update_status_label()
	update_time_bar()

func update_level_label() -> void:
	var level_num = level_loader.get_current_level_index()
	if level_loader.level_files[level_num].ends_with("tutorial.txt"):
		level_label.text = "Tutorial"
	else:
		# MODIFIED: Show the correct level number for non-tutorial levels
		var tutorial_count = 0
		for file in level_loader.level_files:
			if file.ends_with("tutorial.txt"):
				tutorial_count += 1
		level_label.text = "Level: %d" % (level_num - tutorial_count + 1)


func update_status_label() -> void:
	status_label.text = player.get_recording_status()

func update_time_bar() -> void:
	time_bar.max_value = player.max_recording_time
	time_bar.value = player.remaining_recording_time

func show_tutorial(key: String):
	if key in shown_tutorials or not key in tutorial_messages:
		return
	
	current_tutorial_key = key
	shown_tutorials.append(key)
	tutorial_label.text = tutorial_messages[key]
	tutorial_panel.show()

func hide_tutorial(key: String):
	if current_tutorial_key == key:
		tutorial_panel.hide()
		current_tutorial_key = ""

# --- NEW FUNCTION ---
func hide_all_tutorials():
	if tutorial_panel.visible:
		tutorial_panel.hide()
		current_tutorial_key = ""

func on_level_generated(_player_start_pos):
	shown_tutorials.clear()
	hide_all_tutorials()
