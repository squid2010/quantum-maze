extends Control

@onready var main_view: VBoxContainer = $CenterContainer/VBoxContainer
@onready var credits_panel: Panel = $CreditsPanel
@onready var settings_panel: Panel = $SettingsPanel
@onready var music_slider: HSlider = $SettingsPanel/CenterContainer/VBoxContainer/MusicControl/MusicSlider
@onready var button_sound: AudioStreamPlayer = $ButtonSound

func _ready():
	# --- Button Connections ---
	var buttons = main_view.get_node("MenuButtons").get_children()
	buttons.append(credits_panel.get_node("CenterContainer/VBoxContainer/BackButton"))
	buttons.append(settings_panel.get_node("CenterContainer/VBoxContainer/BackButton"))
	
	for button in buttons:
		button.pressed.connect(_on_button_pressed.bind(button.name))
		button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
		button.mouse_exited.connect(_on_button_mouse_exited.bind(button))

	# --- Music Slider Setup ---
	var music_bus_idx = AudioServer.get_bus_index("Music")
	music_slider.value = AudioServer.get_bus_volume_db(music_bus_idx)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
	# --------------------------
	
	# Hide panels by default
	credits_panel.hide()
	settings_panel.hide()

func _play_button_sound():
	if is_instance_valid(button_sound):
		button_sound.play()

func _on_button_pressed(button_name: String):
	_play_button_sound()
	match button_name:
		"PlayButton":
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		"SettingsButton":
			main_view.hide()
			settings_panel.show()
		"CreditsButton":
			main_view.hide()
			credits_panel.show()
		"QuitButton":
			get_tree().quit()
		"BackButton":
			credits_panel.hide()
			settings_panel.hide()
			main_view.show()

func _on_button_mouse_entered(button: Button):
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.1, 1.1), 0.1)

func _on_button_mouse_exited(button: Button):
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.1)

func _on_music_slider_value_changed(value: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), value)
