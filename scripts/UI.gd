extends CanvasLayer

@onready var level_label: Label = $TopBar/MarginContainer/HBoxContainer/VBoxContainer/LevelLabel
@onready var status_label: Label = $TopBar/MarginContainer/HBoxContainer/VBoxContainer/StatusLabel
@onready var time_bar: ProgressBar = $TopBar/MarginContainer/HBoxContainer/VBoxContainer/TimeBar
@onready var tutorial_panel: Panel = $TutorialPanel
@onready var tutorial_label: RichTextLabel = $TutorialPanel/TutorialLabel
@onready var pause_menu: Control = $PauseMenu
@onready var button_sound: AudioStreamPlayer = $ButtonSound
@onready var music_slider: HSlider = $PauseMenu/CenterContainer/VBoxContainer/MusicControl/MusicSlider

@onready var player: Player = get_tree().root.get_node("main/World/Player")
@onready var level_loader: LevelLoader = get_tree().root.get_node("main/World/LevelLoader")

var tutorial_messages = {
	"MOVE": "Use the [b]Arrow Keys[/b] or [b]WASD[/b] to move.",
	"GOAL": "The [color=lightgreen]Goal[/color] is your objective. Reach it to proceed to the next level.",
	"SWITCH": "This is a [color=yellow]Switch[/color]. Interact with it using [b]Enter[/b] or [b]Spacebar[/b] when nearby.",
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
	pause_menu.hide()
	
	if is_instance_valid(level_loader):
		level_loader.level_generated.connect(on_level_generated)

	pause_menu.get_node("CenterContainer/VBoxContainer/Buttons/ResumeButton").pressed.connect(_on_ResumeButton_pressed)
	pause_menu.get_node("CenterContainer/VBoxContainer/Buttons/RestartButton").pressed.connect(_on_RestartButton_pressed)
	pause_menu.get_node("CenterContainer/VBoxContainer/Buttons/QuitButton").pressed.connect(_on_QuitButton_pressed)
	
	$TopBar/MarginContainer/HBoxContainer/PauseButton.pressed.connect(_on_PauseButton_pressed)

	var music_bus_idx = AudioServer.get_bus_index("Music")
	music_slider.value = AudioServer.get_bus_volume_db(music_bus_idx)
	music_slider.value_changed.connect(_on_music_slider_value_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_tree().get_root().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(level_loader):
		return
		
	if get_tree().paused:
		return

	update_level_label()
	update_status_label()
	update_time_bar()

# NEW: Connects to the player's 'echo_created' signal.
func on_echo_created(echo_instance: QuantumEcho):
	if is_instance_valid(echo_instance):
		echo_instance.time_consumed.connect(on_echo_time_consumed)

# NEW: Called every frame by an active echo to drain the time bar smoothly.
func on_echo_time_consumed(amount: float):
	if is_instance_valid(player):
		player.remaining_recording_time -= amount
		# Ensure time doesn't go below zero
		player.remaining_recording_time = max(0.0, player.remaining_recording_time)

func _play_button_sound():
	if is_instance_valid(button_sound):
		button_sound.play(0.05)

func _toggle_pause():
	get_tree().paused = not get_tree().paused
	pause_menu.visible = get_tree().paused
	if get_tree().paused:
		_play_button_sound()

func _on_PauseButton_pressed():
	_toggle_pause()

func _on_ResumeButton_pressed():
	_play_button_sound()
	_toggle_pause()

func _on_RestartButton_pressed():
	_play_button_sound()
	if get_tree().paused:
		_toggle_pause()
	if is_instance_valid(level_loader):
		level_loader.generate()

func _on_QuitButton_pressed():
	_play_button_sound()
	get_tree().quit()

func _on_music_slider_value_changed(value: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), value)

func update_level_label() -> void:
	var level_num = level_loader.get_current_level_index()
	if level_loader.level_files[level_num].ends_with("tutorial.txt"):
		level_label.text = "Tutorial"
	else:
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
	if get_tree().paused:
		return
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

func hide_all_tutorials():
	if tutorial_panel.visible:
		tutorial_panel.hide()
		current_tutorial_key = ""

func on_level_generated(_player_start_pos):
	shown_tutorials.clear()
	hide_all_tutorials()
