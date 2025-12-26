extends Node

class_name FlightManager

static var instance: FlightManager
var _frame_count: int = 0
static var _global_last_process_frame: int = -1

# Large-scale systems
var mass_aircraft_system: MassAircraftSystem
var mass_ai_system: MassAISystem
var mass_ground_system: MassGroundSystem
var use_mass_system: bool = false

# Systems
var projectile_system: ProjectilePoolSystem
var missile_system: MissilePoolSystem
var aircraft_registry: AircraftRegistry
var ai_scheduler: AIThreadScheduler
var cached_aircrafts: Array[Node] = []

func _ready() -> void:
	_setup_systems()
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

var aircrafts: Array[Node]: 
	get: 
		return aircraft_registry.aircrafts if aircraft_registry else []
var spatial_grid: SpatialGrid: 
	get: 
		return aircraft_registry.spatial_grid if aircraft_registry else null

func register_aircraft(a: Node) -> void: if aircraft_registry: aircraft_registry.register_aircraft(a)
func unregister_aircraft(a: Node) -> void: if aircraft_registry: aircraft_registry.unregister_aircraft(a)
func get_aircraft_data_by_id(id: int) -> Dictionary: return aircraft_registry.get_aircraft_data_by_id(id) if aircraft_registry else {}
func get_enemies_of(team: int) -> Array[Dictionary]: return aircraft_registry.get_enemies_of(team) if aircraft_registry else []

func _setup_mass_systems() -> void:
	mass_aircraft_system = MassAircraftSystem.new()
	add_child(mass_aircraft_system)
	mass_ai_system = MassAISystem.new()
	add_child(mass_ai_system)
	mass_ai_system.initialize(mass_aircraft_system.MAX_AIRCRAFT)
	mass_ground_system = MassGroundSystem.new()
	add_child(mass_ground_system)
	var ground_ai = MassGroundAI.new()
	add_child(ground_ai)
	ground_ai.initialize(mass_ground_system.MAX_VEHICLES)
	ground_ai.set_ground_system(mass_ground_system)

func _exit_tree() -> void: if instance == self: instance = null
func register_ai(ai: Node) -> void: if ai_scheduler: ai_scheduler.register_ai(ai)
func unregister_ai(ai: Node) -> void: if ai_scheduler: ai_scheduler.unregister_ai(ai)
func spawn_projectile(tf: Transform3D) -> void: if projectile_system: projectile_system.spawn_projectile(tf)
func spawn_missile(tf: Transform3D, target: Node3D, shooter: Node3D) -> void: if missile_system: missile_system.spawn_missile(tf, target, shooter)
func return_missile(m: Missile) -> void: if missile_system: missile_system.return_missile(m)

func _enter_tree() -> void:
	if instance != null and instance != self:
		queue_free()
		return
	instance = self

func _process(delta: float) -> void:
	# 1. Global Singleton Guard (Render Frame Level)
	var current_frame = Engine.get_frames_drawn()
	if FlightManager._global_last_process_frame == current_frame:
		return
	FlightManager._global_last_process_frame = current_frame
	
	_frame_count += 1
	
	# 2. Run all heavy management tasks once per frame
	_run_heavy_updates(delta, current_frame)

# Remove the old _physics_process entirely

var _update_phase: int = 0

func _run_heavy_updates(delta: float, frame: int) -> void:
	# Phase 0: Registry (MUST run every frame for data consistency)
	if aircraft_registry:
		cached_aircrafts = aircraft_registry.aircrafts
		aircraft_registry.update_registry(frame)
	
	# Interleaved Heavy Tasks: Only ONE heavy task per frame
	_update_phase = (_update_phase + 1) % 3
	
	match _update_phase:
		0: # Task 1: AI Processing
			if ai_scheduler and aircraft_registry:
				ai_scheduler.process_ai_batch(delta, aircraft_registry)
		
		1: # Task 2: Projectile System (More frequent updates inside)
			var space_state = null
			if cached_aircrafts.size() > 0 and is_instance_valid(cached_aircrafts[0]):
				space_state = cached_aircrafts[0].get_world_3d().direct_space_state
			
			if projectile_system and space_state:
				projectile_system.update_projectiles(delta, space_state, frame)
		
		2: # Task 3: Mass System & Ground Logic
			if use_mass_system: _process_mass_system(delta)
			# Potential for other ground systems here

func _process_mass_system(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	var cam_pos = player.global_position if is_instance_valid(player) else Vector3.ZERO
	mass_ai_system.process_ai_batch(delta, mass_aircraft_system, cam_pos)
	mass_ai_system.apply_ai_to_mass_system(mass_aircraft_system)

func spawn_mass_aircraft(pos: Vector3, team: int, rot: Vector3 = Vector3.ZERO) -> int: return mass_aircraft_system.spawn_aircraft(pos, team, rot)
func spawn_formation(center: Vector3, team: int, count: int, spacing: float = 50.0, rot: Vector3 = Vector3.ZERO) -> void:
	for i in range(count):
		var offset = Vector3((i % 5 - 2) * spacing, (i / 5) * 2.0, -(i / 5) * spacing)
		spawn_mass_aircraft(center + offset, team, rot)
