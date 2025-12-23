extends Node3D

@export var ally_scene: PackedScene = preload("res://Scenes/Entities/AllyAircraft.tscn")
@export var enemy_scene: PackedScene = preload("res://Scenes/Entities/EnemyAircraft.tscn")
@export var ally_count: int = 150
@export var enemy_count: int = 150
@export var spawn_radius: float = 1000.0

# Mass system settings (NEW)
@export_group("Mass System")
@export var use_mass_system: bool = false # Toggle between legacy and mass system
@export var mass_ally_count: int = 500
@export var mass_enemy_count: int = 500

# Ground vehicle settings (NEW)
@export_group("Ground Vehicles")
@export var spawn_ground_vehicles: bool = true
@export var ground_vehicle_scene: PackedScene = preload("res://Scenes/Ground/Tank.tscn")
@export var capture_zone_scene: PackedScene = preload("res://Scenes/Ground/CaptureZone.tscn")
@export var ally_ground_count: int = 10
@export var enemy_ground_count: int = 10
@export var ground_spawn_radius: float = 800.0

@onready var aircraft: Aircraft = $Aircraft
@onready var hud: HUD = $CanvasLayer/HUD
@onready var ground_system: MassGroundSystem = null

var pause_menu_scene = preload("res://Scenes/UI/PauseMenu.tscn")
var game_over: bool = false
var max_allies_count: int = 0
var max_enemies_count: int = 0
var _startup_delay: float = 2.0

var ally_base_pos: Vector3
var enemy_base_pos: Vector3

# Spawn Queue System (legacy)
var _spawn_queue: Array = []
var _spawn_per_frame: int = 5 # Reduced from 10 to prevent lag spikes
var _is_spawning: bool = false

func _ready() -> void:
	# Disable accumulated input for lower latency (useful for flight sims/FPS)
	Input.set_use_accumulated_input(false)
	
	# Initialize FlightManager
	var flight_manager = FlightManager.new()
	add_child(flight_manager)
	
	# Initialize Ground System if needed
	if spawn_ground_vehicles:
		ground_system = MassGroundSystem.new()
		add_child(ground_system)
	
	# Use exclusive fullscreen for better performance and true fullscreen experience
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	# Setup Capture Zones
	_setup_capture_zones()
	
	if aircraft and hud:
		hud.set_aircraft(aircraft)
		# Position player in the South (Ally side) facing North
		aircraft.global_position = Vector3(0, 400, spawn_radius + 200.0)
		aircraft.rotation_degrees = Vector3.ZERO
		# Ensure player starts with some speed
		if "current_speed" in aircraft:
			aircraft.current_speed = aircraft.max_speed * 0.8
		if "throttle" in aircraft:
			aircraft.throttle = 0.8
	
	# Choose spawn method based on use_mass_system
	if use_mass_system:
		_spawn_mass_aircraft()
	else:
		# Queue aircraft for gradual spawning instead of all at once
		queue_aircraft_spawn(ally_scene, ally_count, GlobalEnums.Team.ALLY)
		queue_aircraft_spawn(enemy_scene, enemy_count, GlobalEnums.Team.ENEMY)
		
		# Set expected counts
		max_allies_count = ally_count
		max_enemies_count = enemy_count
		
		_is_spawning = true
		if hud:
			hud.show_game_over("Loading...")
	
	# Spawn ground vehicles
	if spawn_ground_vehicles:
		_spawn_ground_vehicles()
	
	# Add Pause Menu
	var pause_menu = pause_menu_scene.instantiate()
	$CanvasLayer.add_child(pause_menu)

func _spawn_mass_aircraft() -> void:
	if not FlightManager.instance:
		push_error("[MainLevel] FlightManager not initialized")
		return
	
	FlightManager.instance.use_mass_system = true
	
	# Spawn allies in formation (South Side, Facing North)
	# Z > 0 is South. Facing North means facing -Z (Rotation 0).
	var ally_center = Vector3(0, 400, spawn_radius)
	FlightManager.instance.spawn_formation(ally_center, GlobalEnums.Team.ALLY, mass_ally_count, 50.0, Vector3.ZERO)
	
	# Spawn enemies in formation (North Side, Facing South)
	# Z < 0 is North. Facing South means facing +Z (Rotation PI).
	var enemy_center = Vector3(0, 400, -spawn_radius)
	FlightManager.instance.spawn_formation(enemy_center, GlobalEnums.Team.ENEMY, mass_enemy_count, 50.0, Vector3(0, PI, 0))
	
	max_allies_count = mass_ally_count
	max_enemies_count = mass_enemy_count
	
	print("[MainLevel] Spawned ", mass_ally_count, " allies and ", mass_enemy_count, " enemies using mass system")

func _setup_capture_zones() -> void:
	if not capture_zone_scene: return
	
	# Ally Base (South)
	ally_base_pos = Vector3(0, 0, 1000)
	var ally_zone = capture_zone_scene.instantiate()
	ally_zone.owning_team = GlobalEnums.Team.ALLY
	ally_zone.base_captured.connect(_on_base_captured)
	add_child(ally_zone)
	# Set position AFTER adding to tree
	ally_zone.global_position = ally_base_pos
	
	var mat_ally = StandardMaterial3D.new()
	mat_ally.albedo_color = Color(0.2, 0.4, 1.0) # Blue
	ally_zone.get_node("Visual/Flag").set_surface_override_material(0, mat_ally)
	
	# Enemy Base (North)
	enemy_base_pos = Vector3(0, 0, -1000)
	var enemy_zone = capture_zone_scene.instantiate()
	enemy_zone.owning_team = GlobalEnums.Team.ENEMY
	enemy_zone.base_captured.connect(_on_base_captured)
	add_child(enemy_zone)
	# Set position AFTER adding to tree
	enemy_zone.global_position = enemy_base_pos
	
	var mat_enemy = StandardMaterial3D.new()
	mat_enemy.albedo_color = Color(1.0, 0.2, 0.2) # Red
	enemy_zone.get_node("Visual/Flag").set_surface_override_material(0, mat_enemy)
	
	print("[MainLevel] Capture Zones setup complete.")

func _on_base_captured(capturing_team: int) -> void:
	if game_over: return
	game_over = true
	
	if capturing_team == GlobalEnums.Team.ALLY:
		hud.show_game_over("VICTORY! Enemy Base Captured!")
	else:
		hud.show_game_over("DEFEAT! Ally Base Captured!")

func _spawn_ground_vehicles() -> void:
	if not ground_vehicle_scene:
		ground_vehicle_scene = load("res://Scenes/Ground/Tank.tscn")
		if not ground_vehicle_scene:
			push_error("Failed to load Tank.tscn")
			return
	
	print("[MainLevel] Spawning Ground Vehicles...")
	
	# Ally Group (South Side: Z > 0) -> Move to Enemy Base (North)
	var ally_spawn_center = Vector3(0, 20, 1000) # Increased spawn height for safety
	for i in range(ally_ground_count):
		var unit = ground_vehicle_scene.instantiate()
		unit.faction = GlobalEnums.Team.ALLY
		add_child(unit)
		
		var random_pos = Vector3(
			randf_range(-ground_spawn_radius, ground_spawn_radius),
			5.0,
			randf_range(500, 500 + ground_spawn_radius)
		)
		unit.global_position = random_pos
		
		# Set Waypoints
		var ai = unit.get_node_or_null("GroundAI")
		if ai:
			var waypoints: Array[Vector3] = [enemy_base_pos]
			ai.set_waypoints(waypoints)
	
	# Enemy Group (North Side: Z < 0) -> Move to Ally Base (South)
	var enemy_spawn_center = Vector3(0, 20, -1000)
	for i in range(enemy_ground_count):
		var unit = ground_vehicle_scene.instantiate()
		unit.faction = GlobalEnums.Team.ENEMY
		add_child(unit)
		
		var random_pos = Vector3(
			randf_range(-ground_spawn_radius, ground_spawn_radius),
			5.0,
			randf_range(-500 - ground_spawn_radius, -500)
		)
		unit.global_position = random_pos
		
		# Set Waypoints
		var ai = unit.get_node_or_null("GroundAI")
		if ai:
			var waypoints: Array[Vector3] = [ally_base_pos]
			ai.set_waypoints(waypoints)
	
	print("[MainLevel] Spawned ", ally_ground_count, " ally and ", enemy_ground_count, " enemy tanks with objectives.")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# --- R Key: Camera Mode ---
		if event.keycode == KEY_R:
			print("[MainLevel] R key pressed. Toggling Camera Mode...")
			var player_dead = not is_instance_valid(aircraft) or (aircraft.get("current_health") != null and aircraft.current_health <= 0)
			if player_dead:
				var cam = get_viewport().get_camera_3d()
				if cam:
					var rig = cam.get_parent()
					if rig and rig.has_method("enable_free_cam"): 
						if rig.get("is_free_cam"):
							print("[MainLevel] Free Cam Active -> Switching to Spectator Mode.")
							rig.enable_spectator_mode()
						else:
							print("[MainLevel] Spectator Active -> Switching to Free Cam.")
							rig.enable_free_cam()
			else:
				print("[MainLevel] Player is still alive. Camera toggle denied.")
		
		# --- Time Scale (Numpad or Top Row) ---
		elif event.keycode == KEY_1 or event.keycode == KEY_KP_1:
			Engine.time_scale = 1.0
			print("[Time Scale] 1.0x (Normal)")
		elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
			Engine.time_scale = 2.0
			print("[Time Scale] 2.0x (Fast)")
		elif event.keycode == KEY_3 or event.keycode == KEY_KP_3:
			Engine.time_scale = 4.0
			print("[Time Scale] 4.0x (Very Fast)")
		elif event.keycode == KEY_4 or event.keycode == KEY_KP_4:
			Engine.time_scale = 0.5
			print("[Time Scale] 0.5x (Slow)")

		# --- Debug: Wing Break (Y/T) ---
		elif event.keycode == KEY_Y or event.keycode == KEY_T:
			var target_to_break = null
			
			# Priority 1: Locked Target
			if is_instance_valid(aircraft) and is_instance_valid(aircraft.locked_target):
				target_to_break = aircraft.locked_target
			
			# Priority 2: Closest Enemy
			if not target_to_break and FlightManager.instance:
				var min_dist = 99999.0
				var p_pos = aircraft.global_position if is_instance_valid(aircraft) else Vector3.ZERO
				for a in FlightManager.instance.aircrafts:
					if is_instance_valid(a) and a != aircraft and a.team != GlobalEnums.Team.ALLY:
						var d = p_pos.distance_squared_to(a.global_position)
						if d < min_dist:
							min_dist = d
							target_to_break = a
			
			if target_to_break:
				if event.keycode == KEY_Y:
					print("[Debug] Breaking Left Wing of ", target_to_break.name)
					target_to_break.break_part("l_wing_out")
				elif event.keycode == KEY_T:
					print("[Debug] Breaking Right Wing of ", target_to_break.name)
					target_to_break.break_part("r_wing_out")
			else:
				print("[Debug] No target found to break wings.")



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
				hud.hide_game_over() # Hide loading message
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
		if use_mass_system:
			# Use mass system counts
			allies_count = FlightManager.instance.mass_aircraft_system.ally_count
			enemies_count = FlightManager.instance.mass_aircraft_system.enemy_count
		else:
			# Optimization: Use cached lists from FlightManager
			allies_count = FlightManager.instance.get_enemies_of(GlobalEnums.Team.ENEMY).size()
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
		var pos_x = randf_range(-spawn_radius, spawn_radius)
		var pos_y = randf_range(300, 600)
		var pos_z = 0.0
		var rot_y = 0.0
		
		if team == GlobalEnums.Team.ALLY:
			# Allies: South side (Positive Z), facing North (0)
			pos_z = randf_range(spawn_radius, spawn_radius + 1000.0)
			rot_y = randf_range(-10.0, 10.0)
		else:
			# Enemies: North side (Negative Z), facing South (180)
			pos_z = randf_range(-spawn_radius - 1000.0, -spawn_radius)
			rot_y = randf_range(170.0, 190.0)
			
		var spawn_pos = Vector3(pos_x, pos_y, pos_z)
		
		_spawn_queue.append({
			"scene": scene,
			"team": team,
			"position": spawn_pos,
			"rotation": rot_y
		})

func instantiate_aircraft(scene: PackedScene, _team: int, pos: Vector3, rot_y: float) -> void:
	var unit = scene.instantiate()
	add_child(unit)
	
	unit.global_position = pos
	unit.rotation_degrees.y = rot_y
	
	# Give initial speed to prevent stalling
	unit.current_speed = unit.max_speed * 0.8
	unit.throttle = 0.8
