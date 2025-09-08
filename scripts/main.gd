extends Node2D

@onready var level_loader = $World/LevelLoader
@onready var player = $World/Player

# The amount of extra space to show around the maze, as a percentage of window size
const PADDING = 0.1

func _ready():
	level_loader.level_generated.connect(_on_level_generated)

func _on_level_generated(_player_start_pos):
	# Wait one frame for the level to be fully drawn before calculating zoom
	await get_tree().process_frame
	
	var camera = player.get_node_or_null("Camera2D")
	if not camera:
		return
		
	# Get the total size of the maze in pixels
	var maze_pixel_size = level_loader.get_maze_size() * level_loader.cell_size
	
	# Get the size of the game window (viewport)
	var viewport_size = get_viewport().size
	
	# We need to account for the UI at the top, so we reduce the available height
	var ui_height = $UI.get_node("TopBar").size.y
	var available_viewport_size = Vector2(viewport_size.x, viewport_size.y - ui_height)
	
	# Calculate the required zoom to fit the maze based on its width and height
	# Add a small buffer to prevent the maze from touching the edges
	var zoom_x = maze_pixel_size.x / (available_viewport_size.x * (1.0 - PADDING))
	var zoom_y = maze_pixel_size.y / (available_viewport_size.y * (1.0 - PADDING))
	
	# The camera zoom needs to be the larger of the two values to ensure everything fits
	var new_zoom = max(zoom_x, zoom_y)
	
	# We don't want to zoom in too far on small levels, so we cap the minimum zoom
	new_zoom = max(new_zoom, 0.75) # Allow slight zoom-out for better feel
	
	camera.zoom = Vector2(new_zoom, new_zoom)
