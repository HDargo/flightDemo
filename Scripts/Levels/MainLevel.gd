extends Node3D

@export var ally_scene: PackedScene = preload("res://Scenes/Entities/AllyAircraft.tscn")
@export var enemy_scene: PackedScene = preload("res://Scenes/Entities/EnemyAircraft.tscn")
@export var player_base_scene: PackedScene = preload("res://Scenes/Entities/Aircraft.tscn")
@export var aircraft_options: Array[AircraftResource] = [
	preload("res://Resources/Aircraft/FProto.tres"),
	preload("res://Resources/Aircraft/AHeavy.tres"),
	preload("res://Resources/Aircraft/Swift.tres"),
	preload("res://Resources/Aircraft/Titan.tres")
]

@export var ally_count: int = 150
@export var enemy_count: int = 150
@export var spawn_radius: float = 1000.0

# Mass system settings
@export_group("Mass System")
@export var use_mass_system: bool = false
@export var mass_ally_count: int = 500
@export var mass_enemy_count: int = 500

# Ground vehicle settings
@export_group("Ground Vehicles")
@export var spawn_ground_vehicles: bool = true
@export var ground_vehicle_scene: PackedScene = preload("res://Scenes/Ground/Tank.tscn")
@export var capture_zone_scene: PackedScene = preload("res://Scenes/Ground/CaptureZone.tscn")
@export var ally_ground_count: int = 10
@export var enemy_ground_count: int = 10
@export var ground_spawn_radius: float = 800.0

@onready var hud: HUD = $CanvasLayer/HUD
@onready var ground_system: MassGroundSystem = null

var selection_menu_scene = preload("res://Scenes/UI/SelectionMenu.tscn")
var aircraft: Aircraft = null # Dynamic player
var game_over: bool = false
var max_allies_count: int = 0
var max_enemies_count: int = 0
var _startup_delay: float = 2.0

var ally_base_pos: Vector3
var enemy_base_pos: Vector3

# Spawn Queue System (legacy)
var _spawn_queue: Array = []
var _spawn_per_frame: int = 5
var _is_spawning: bool = false

func _ready() -> void:
	Input.set_use_accumulated_input(false)
	
	# CRITICAL: Absolute singleton enforcement
	var existing_manager = get_tree().root.find_child("FlightManager", true, false)
	if existing_manager:
		print("[MainLevel] Found existing FlightManager. Linking to it.")
		# We don't need to add a new one
	elif FlightManager.instance == null:
		var flight_manager = FlightManager.new()
		flight_manager.name = "FlightManager"
		add_child(flight_manager)
		print("[MainLevel] FlightManager created and added.")
	else:
		print("[MainLevel] FlightManager static instance exists but node not found. This is unusual.")
	
	if spawn_ground_vehicles:
		ground_system = MassGroundSystem.new()
		add_child(ground_system)
	
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_setup_capture_zones()
	
	# Show Selection Menu
	var menu = selection_menu_scene.instantiate()
	menu.aircrafts = aircraft_options
	menu.aircraft_selected.connect(_on_aircraft_selected)
	$CanvasLayer.add_child(menu)
	
	Engine.time_scale = 0.0

func _on_aircraft_selected(data: AircraftResource) -> void:
	Engine.time_scale = 1.0
	
	# Instantiate Player
	aircraft = player_base_scene.instantiate()
	aircraft.aircraft_data = data
	aircraft.team = GlobalEnums.Team.ALLY
	aircraft.is_player = true
	add_child(aircraft)
	
	if hud:
		hud.set_aircraft(aircraft)
		aircraft.global_position = Vector3(0, 400, spawn_radius + 200.0)
		aircraft.rotation_degrees = Vector3.ZERO
		aircraft.current_speed = data.max_speed * 0.8
		aircraft.throttle = 0.8
	
	_start_game_spawn()

func _start_game_spawn() -> void:
	if use_mass_system:
		_spawn_mass_aircraft()
	else:
		queue_aircraft_spawn(ally_scene, ally_count, GlobalEnums.Team.ALLY)
		queue_aircraft_spawn(enemy_scene, enemy_count, GlobalEnums.Team.ENEMY)
		max_allies_count = ally_count
		max_enemies_count = enemy_count
		_is_spawning = true
		if hud:
			hud.show_game_over("Loading...")
	
	if spawn_ground_vehicles:
		_spawn_ground_vehicles()
	
	var pause_menu_scene = preload("res://Scenes/UI/PauseMenu.tscn")
	var pause_menu = pause_menu_scene.instantiate()
	$CanvasLayer.add_child(pause_menu)

func _spawn_mass_aircraft() -> void:
	if not FlightManager.instance: return
	FlightManager.instance.use_mass_system = true
	
	var ally_center = Vector3(0, 400, spawn_radius)
	FlightManager.instance.spawn_formation(ally_center, GlobalEnums.Team.ALLY, mass_ally_count, 50.0, Vector3.ZERO)
	
	var enemy_center = Vector3(0, 400, -spawn_radius)
	FlightManager.instance.spawn_formation(enemy_center, GlobalEnums.Team.ENEMY, mass_enemy_count, 50.0, Vector3(0, PI, 0))
	
	max_allies_count = mass_ally_count
	max_enemies_count = mass_enemy_count

func _setup_capture_zones() -> void:
	if not capture_zone_scene: return
	ally_base_pos = Vector3(0, 0, 1000)
	var ally_zone = capture_zone_scene.instantiate()
	ally_zone.owning_team = GlobalEnums.Team.ALLY
	ally_zone.base_captured.connect(_on_base_captured)
	add_child(ally_zone)
	ally_zone.global_position = ally_base_pos
	
	enemy_base_pos = Vector3(0, 0, -1000)
	var enemy_zone = capture_zone_scene.instantiate()
	enemy_zone.owning_team = GlobalEnums.Team.ENEMY
	enemy_zone.base_captured.connect(_on_base_captured)
	add_child(enemy_zone)
	enemy_zone.global_position = enemy_base_pos

func _on_base_captured(capturing_team: int) -> void:
	if game_over: return
	game_over = true
	if capturing_team == GlobalEnums.Team.ALLY:
		hud.show_game_over("VICTORY! Enemy Base Captured!")
	else:
		hud.show_game_over("DEFEAT! Ally Base Captured!")

func _spawn_ground_vehicles() -> void:
	if not ground_vehicle_scene: return
	
	for i in range(ally_ground_count):
		var unit = ground_vehicle_scene.instantiate()
		unit.faction = GlobalEnums.Team.ALLY
		add_child(unit)
		unit.global_position = Vector3(randf_range(-ground_spawn_radius, ground_spawn_radius), 5.0, randf_range(500, 500 + ground_spawn_radius))
		var ai = unit.get_node_or_null("GroundAI")
		if ai: 
			var wp: Array[Vector3] = [enemy_base_pos]
			ai.set_waypoints(wp)
	
	for i in range(enemy_ground_count):
		var unit = ground_vehicle_scene.instantiate()
		unit.faction = GlobalEnums.Team.ENEMY
		add_child(unit)
		unit.global_position = Vector3(randf_range(-ground_spawn_radius, ground_spawn_radius), 5.0, randf_range(-500 - ground_spawn_radius, -500))
		var ai = unit.get_node_or_null("GroundAI")
		if ai: 
			var wp: Array[Vector3] = [ally_base_pos]
			ai.set_waypoints(wp)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			var player_dead = not is_instance_valid(aircraft)
			if player_dead:
				var cam = get_viewport().get_camera_3d()
				if cam and cam.get_parent().has_method("enable_free_cam"):
					cam.get_parent().enable_free_cam()
		elif event.keycode == KEY_1: Engine.time_scale = 1.0
		elif event.keycode == KEY_2: Engine.time_scale = 2.0

var _hud_update_timer: float = 0.0

func _process(delta: float) -> void:
	if _is_spawning and _spawn_queue.size() > 0:
		for i in range(_spawn_per_frame):
			if _spawn_queue.is_empty(): break
			var d = _spawn_queue.pop_front()
			instantiate_aircraft(d.scene, d.team, d.position, d.rotation)
		if _spawn_queue.is_empty():
			_is_spawning = false
			if hud: hud.hide_game_over()
		return
	
	if game_over or _startup_delay > 0.0:
		_startup_delay -= delta
		return
	
	_hud_update_timer += delta
	if _hud_update_timer >= 0.1:
		_hud_update_timer = 0.0
		_update_hud_status()

func _update_hud_status() -> void:
	var allies_count = 0
	var enemies_count = 0
	if FlightManager.instance:
		if use_mass_system:
			allies_count = FlightManager.instance.mass_aircraft_system.ally_count
			enemies_count = FlightManager.instance.mass_aircraft_system.enemy_count
		else:
			allies_count = FlightManager.instance.get_enemies_of(GlobalEnums.Team.ENEMY).size()
			enemies_count = FlightManager.instance.get_enemies_of(GlobalEnums.Team.ALLY).size()
	
	if hud:
		hud.update_battle_status(allies_count, enemies_count, max_allies_count, max_enemies_count)
	
	if max_allies_count > 0 and max_enemies_count > 0:
		if enemies_count == 0:
			game_over = true
			hud.show_game_over("VICTORY!")
		elif allies_count == 0 and not is_instance_valid(aircraft):
			game_over = true
			hud.show_game_over("DEFEAT!")

func queue_aircraft_spawn(scene: PackedScene, count: int, team: int) -> void:
	for i in range(count):
		var pos = Vector3(randf_range(-spawn_radius, spawn_radius), randf_range(300, 600), 0)
		if team == GlobalEnums.Team.ALLY:
			pos.z = randf_range(spawn_radius, spawn_radius + 1000)
		else:
			pos.z = randf_range(-spawn_radius - 1000, -spawn_radius)
		_spawn_queue.append({"scene": scene, "team": team, "position": pos, "rotation": 0 if team == GlobalEnums.Team.ALLY else 180})

var _total_spawned_count: int = 0

func instantiate_aircraft(scene: PackedScene, team: int, pos: Vector3, rot_y: float) -> void:
	_total_spawned_count += 1
	# print("[MainLevel] Spawning aircraft #", _total_spawned_count)
	var unit = scene.instantiate()
	
	# Assign default resource based on team
	if "aircraft_data" in unit:
		if team == GlobalEnums.Team.ALLY:
			unit.aircraft_data = preload("res://Resources/Aircraft/AllyProto.tres")
		else:
			unit.aircraft_data = preload("res://Resources/Aircraft/EnemyProto.tres")
	
	add_child(unit)
	
	unit.global_position = pos
	unit.rotation_degrees.y = rot_y
	
	# CRITICAL: Set high initial speed and full throttle to prevent stall-crash
	# Wait one frame for _ready to initialize speed settings from resource
	await get_tree().process_frame
	if is_instance_valid(unit):
		unit.current_speed = unit.max_speed
		unit.velocity = -unit.global_transform.basis.z * unit.current_speed
		unit.throttle = 1.0
