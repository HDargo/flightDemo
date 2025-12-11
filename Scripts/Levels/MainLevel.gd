extends Node3D

@export var ally_scene: PackedScene = preload("res://Scenes/Entities/AllyAircraft.tscn")
@export var enemy_scene: PackedScene = preload("res://Scenes/Entities/EnemyAircraft.tscn")
@export var ally_count: int = 150  # Reduced from 150 for performance
@export var enemy_count: int = 150  # Reduced from 150 for performance
@export var spawn_radius: float = 1000.0

@onready var aircraft: Aircraft = $Aircraft
@onready var hud: HUD = $CanvasLayer/HUD

var pause_menu_scene = preload("res://Scenes/UI/PauseMenu.tscn")
var game_over: bool = false
var max_allies_count: int = 0
var max_enemies_count: int = 0
var _startup_delay: float = 2.0  # Wait 2 seconds for spawn to complete

# Spawn Queue System
var _spawn_queue: Array = []
var _spawn_per_frame: int = 10
var _is_spawning: bool = false

func _ready() -> void:
	# Disable accumulated input for lower latency (useful for flight sims/FPS)
	Input.set_use_accumulated_input(false)
	
	# Initialize FlightManager
	var flight_manager = FlightManager.new()
	add_child(flight_manager)
	
	# Use exclusive fullscreen for better performance and true fullscreen experience
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	if aircraft and hud:
		hud.set_aircraft(aircraft)
	
	# Queue aircraft for gradual spawning instead of all at once
	queue_aircraft_spawn(ally_scene, ally_count, GlobalEnums.Team.ALLY)
	queue_aircraft_spawn(enemy_scene, enemy_count, GlobalEnums.Team.ENEMY)
	
	# Set expected counts
	max_allies_count = ally_count
	max_enemies_count = enemy_count
	
	_is_spawning = true
	if hud:
		hud.show_game_over("Loading...")
	
	# Add Pause Menu
	var pause_menu = pause_menu_scene.instantiate()
	$CanvasLayer.add_child(pause_menu)

var _hud_update_timer: float = 0.0

func _process(delta: float) -> void:
	# Process spawn queue
	if _is_spawning and _spawn_queue.size() > 0:
		var spawned_this_frame = 0
		while spawned_this_frame < _spawn_per_frame and _spawn_queue.size() > 0:
			var spawn_data = _spawn_queue.pop_front()
			instantiate_aircraft(spawn_data.scene, spawn_data.team, spawn_data.position, spawn_data.rotation)
			spawned_this_frame += 1
		
		if _spawn_queue.size() == 0:
			_is_spawning = false
			if hud:
				hud.hide_game_over()  # Hide loading message
		return
	
	if game_over: return
	
	# Wait for startup delay before checking win/loss conditions
	if _startup_delay > 0.0:
		_startup_delay -= delta
		return
	
	# Optimization: Update HUD only 10 times per second, not every frame
	_hud_update_timer += delta
	if _hud_update_timer < 0.1:
		return
	_hud_update_timer = 0.0
	
	var allies_count = 0
	var enemies_count = 0
	
	if FlightManager.instance:
		# Optimization: Use cached lists from FlightManager
		# get_enemies_of(ENEMY) returns Allies list
		allies_count = FlightManager.instance.get_enemies_of(GlobalEnums.Team.ENEMY).size()
		# get_enemies_of(ALLY) returns Enemies list
		enemies_count = FlightManager.instance.get_enemies_of(GlobalEnums.Team.ALLY).size()
	else:
		# Fallback (Slow)
		allies_count = get_tree().get_nodes_in_group("ally").size()
		enemies_count = get_tree().get_nodes_in_group("enemy").size()
	
	if hud:
		hud.update_battle_status(allies_count, enemies_count, max_allies_count, max_enemies_count)
	
	var player_alive = is_instance_valid(aircraft) and not aircraft.is_queued_for_deletion()
	
	# Only check win/loss conditions if we have valid initial counts
	if max_allies_count > 0 and max_enemies_count > 0:
		if enemies_count == 0:
			game_over = true
			hud.show_game_over("VICTORY! All enemies destroyed.")
		elif allies_count == 0 and not player_alive:
			game_over = true
			hud.show_game_over("DEFEAT! All allies destroyed.")

func queue_aircraft_spawn(scene: PackedScene, count: int, team: int) -> void:
	if not scene: return
	
	for i in range(count):
		# Random position around center or player
		var random_pos = Vector3(
			randf_range(-spawn_radius, spawn_radius),
			randf_range(300, 600), # Higher start
			randf_range(-spawn_radius, spawn_radius)
		)
		
		# Offset enemies further away
		if team == GlobalEnums.Team.ENEMY:
			random_pos.z -= 400 # Start in front
		else:
			random_pos.z += 50 # Start behind/near player
		
		var rotation_y = randf_range(0, 360)
		
		_spawn_queue.append({
			"scene": scene,
			"team": team,
			"position": random_pos,
			"rotation": rotation_y
		})

func instantiate_aircraft(scene: PackedScene, _team: int, pos: Vector3, rot_y: float) -> void:
	var unit = scene.instantiate()
	add_child(unit)
	
	unit.global_position = pos
	unit.rotation_degrees.y = rot_y
	
	# Give initial speed to prevent stalling
	unit.current_speed = unit.max_speed * 0.8
	unit.throttle = 0.8
