extends Node

class_name FlightManager

static var instance: FlightManager

var _frame_count: int = 0

# Large-scale systems (NEW)
var mass_aircraft_system: MassAircraftSystem
var mass_ai_system: MassAISystem
var mass_ground_system: MassGroundSystem
var use_mass_system: bool = false # Toggle for testing

# Systems
var projectile_system: ProjectilePoolSystem
var missile_system: MissilePoolSystem
var aircraft_registry: AircraftRegistry
var ai_scheduler: AIThreadScheduler

func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	# Reserve 1 core for Main Thread/Audio to prevent starvation (WASAPI errors)
	# _thread_count logic moved to AIThreadScheduler
	
	_setup_systems()
	
	# Initialize mass systems
	_setup_mass_systems()

func _setup_systems() -> void:
	projectile_system = ProjectilePoolSystem.new()
	projectile_system.name = "ProjectilePoolSystem"
	add_child(projectile_system)
	
	missile_system = MissilePoolSystem.new()
	missile_system.name = "MissilePoolSystem"
	add_child(missile_system)
	
	aircraft_registry = AircraftRegistry.new()
	aircraft_registry.name = "AircraftRegistry"
	add_child(aircraft_registry)
	
	ai_scheduler = AIThreadScheduler.new()
	ai_scheduler.name = "AIThreadScheduler"
	add_child(ai_scheduler)
	
	# Expose spatial grid alias for compatibility if needed
	# spatial_grid = aircraft_registry.spatial_grid 

# Forwarding Properties (for compatibility during refactor)
var aircrafts: Array[Node]:
	get: return aircraft_registry.aircrafts
var spatial_grid: SpatialGrid:
	get: return aircraft_registry.spatial_grid

func register_aircraft(a: Node) -> void:
	if aircraft_registry:
		aircraft_registry.register_aircraft(a)

func unregister_aircraft(a: Node) -> void:
	if aircraft_registry:
		aircraft_registry.unregister_aircraft(a)

func get_aircraft_data(node: Node) -> Dictionary:
	if aircraft_registry:
		return aircraft_registry.get_aircraft_data(node)
	return {}

func get_aircraft_data_by_id(id: int) -> Dictionary:
	if aircraft_registry:
		return aircraft_registry.get_aircraft_data_by_id(id)
	return {}

func get_enemies_of(team: int) -> Array[Dictionary]:
	if aircraft_registry:
		return aircraft_registry.get_enemies_of(team)
	return []

func _setup_mass_systems() -> void:
	# Create MassAircraftSystem
	mass_aircraft_system = MassAircraftSystem.new()
	mass_aircraft_system.name = "MassAircraftSystem"
	add_child(mass_aircraft_system)
	
	# Create MassAISystem
	mass_ai_system = MassAISystem.new()
	mass_ai_system.name = "MassAISystem"
	add_child(mass_ai_system)
	mass_ai_system.initialize(mass_aircraft_system.MAX_AIRCRAFT)
	
	# Create MassGroundSystem
	mass_ground_system = MassGroundSystem.new()
	mass_ground_system.name = "MassGroundSystem"
	add_child(mass_ground_system)
	
	# Create MassGroundAI
	var ground_ai = MassGroundAI.new()
	ground_ai.name = "MassGroundAI"
	add_child(ground_ai)
	ground_ai.initialize(mass_ground_system.MAX_VEHICLES)
	ground_ai.set_ground_system(mass_ground_system)
	
	print("[FlightManager] Mass systems initialized for 1000+ aircraft and 500+ ground vehicles")

func _exit_tree() -> void:
	if instance == self:
		instance = null

func register_ai(ai: Node) -> void:
	if ai_scheduler:
		ai_scheduler.register_ai(ai)

func unregister_ai(ai: Node) -> void:
	if ai_scheduler:
		ai_scheduler.unregister_ai(ai)

func spawn_projectile(tf: Transform3D) -> void:
	if projectile_system:
		projectile_system.spawn_projectile(tf)

func return_projectile(p: Node) -> void:
	if projectile_system:
		projectile_system.return_projectile(p)

func spawn_missile(tf: Transform3D, target: Node3D, shooter: Node3D) -> void:
	if missile_system:
		missile_system.spawn_missile(tf, target, shooter)

func return_missile(m: Missile) -> void:
	if missile_system:
		missile_system.return_missile(m)

# Cached references to avoid getter overhead
var cached_aircrafts: Array[Node] = []
static var _last_physics_frame: int = -1

func _physics_process(delta: float) -> void:
	# CRITICAL: Prevent ANY instance from running if another already did this frame
	var current_frame = Engine.get_physics_frames()
	if _last_physics_frame == current_frame:
		return
	_last_physics_frame = current_frame
	
	_frame_count += 1
	
	# Update cached reference once per frame
	if aircraft_registry:
		cached_aircrafts = aircraft_registry.aircrafts
		aircraft_registry.update_registry(_frame_count)
	
	# Start AI processing less frequently (every 3 physics frames for better performance)
	if ai_scheduler and aircraft_registry:
		ai_scheduler.process_ai_batch(delta, aircraft_registry)
	
	# Projectile Movement
	var space_state = null
	if aircraft_registry and not aircraft_registry.aircrafts.is_empty():
		var first_aircraft = aircraft_registry.aircrafts[0]
		if is_instance_valid(first_aircraft):
			space_state = first_aircraft.get_world_3d().direct_space_state
	
	if projectile_system and space_state:
		projectile_system.update_projectiles(delta, space_state, _frame_count)

func _process_mass_system(delta: float) -> void:
	if not mass_aircraft_system or not mass_ai_system:
		return
	
	# Get camera position (from player or main camera)
	var camera_pos = Vector3.ZERO
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		camera_pos = player.global_position
	else:
		var camera = get_viewport().get_camera_3d()
		if camera:
			camera_pos = camera.global_position
	
	# Process AI
	mass_ai_system.process_ai_batch(delta, mass_aircraft_system, camera_pos)
	mass_ai_system.apply_ai_to_mass_system(mass_aircraft_system)
	
	# Mass system physics and rendering handled in its own _physics_process

# Helper functions for spawning mass aircraft
func spawn_mass_aircraft(position: Vector3, team: int, rotation: Vector3 = Vector3.ZERO) -> int:
	if not mass_aircraft_system:
		push_error("[FlightManager] MassAircraftSystem not initialized")
		return -1
	
	return mass_aircraft_system.spawn_aircraft(position, team, rotation)

func destroy_mass_aircraft(index: int) -> void:
	if not mass_aircraft_system:
		return
	
	mass_aircraft_system.destroy_aircraft(index)

func spawn_formation(center: Vector3, team: int, count: int, spacing: float = 50.0, rotation: Vector3 = Vector3.ZERO) -> void:
	# Spawn aircraft in V-formation
	for i in range(count):
		var row = i / 5
		var col = i % 5
		
		var offset = Vector3(
			(col - 2) * spacing,
			row * 2.0, # Slight upward stagger instead of diving down
			- row * spacing
		)
		
		spawn_mass_aircraft(center + offset, team, rotation)
