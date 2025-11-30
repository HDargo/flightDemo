extends Node3D

@export var ally_scene: PackedScene = preload("res://Scenes/Entities/AllyAircraft.tscn")
@export var enemy_scene: PackedScene = preload("res://Scenes/Entities/EnemyAircraft.tscn")
@export var ally_count: int = 150
@export var enemy_count: int = 150
@export var spawn_radius: float = 1000.0

@onready var aircraft: Aircraft = $Aircraft
@onready var hud: HUD = $CanvasLayer/HUD

var pause_menu_scene = preload("res://Scenes/UI/PauseMenu.tscn")
var game_over: bool = false
var max_allies_count: int = 0
var max_enemies_count: int = 0

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
	
	spawn_aircraft(ally_scene, ally_count, GlobalEnums.Team.ALLY)
	spawn_aircraft(enemy_scene, enemy_count, GlobalEnums.Team.ENEMY)
	
	# Initial counts
	# Note: Player might not be in "ally" group depending on team setting.
	# Assuming Player is counted as an ally for the bar if they are fighting enemies.
	# But let's stick to group counts for now.
	var allies = get_tree().get_nodes_in_group("ally")
	var enemies = get_tree().get_nodes_in_group("enemy")
	max_allies_count = allies.size()
	max_enemies_count = enemies.size()
	
	# Add Pause Menu
	var pause_menu = pause_menu_scene.instantiate()
	$CanvasLayer.add_child(pause_menu)

func _process(_delta: float) -> void:
	if game_over: return
	
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
	
	if enemies_count == 0:
		game_over = true
		hud.show_game_over("VICTORY! All enemies destroyed.")
	elif allies_count == 0 and not player_alive:
		game_over = true
		hud.show_game_over("DEFEAT! All allies destroyed.")

func spawn_aircraft(scene: PackedScene, count: int, team: int) -> void:
	if not scene: return
	
	for i in range(count):
		var unit = scene.instantiate()
		add_child(unit)
		
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
			
		unit.global_position = random_pos
		unit.rotation_degrees.y = randf_range(0, 360)
		
		# Give initial speed to prevent stalling
		unit.current_speed = unit.max_speed * 0.8
		unit.throttle = 0.8
