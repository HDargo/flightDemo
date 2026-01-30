extends Node

class_name MassAircraftSystem

## Large-scale aircraft simulation using PackedArrays and GPU Compute Shaders
## Handles 1000+ aircraft efficiently

static var instance: MassAircraftSystem

# Packed Arrays for CPU-side data (Thread-safe)
var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var rotations: PackedVector3Array = PackedVector3Array()  # Euler angles
var speeds: PackedFloat32Array = PackedFloat32Array()
var throttles: PackedFloat32Array = PackedFloat32Array()
var healths: PackedFloat32Array = PackedFloat32Array()
var teams: PackedInt32Array = PackedInt32Array()
var states: PackedInt32Array = PackedInt32Array()  # Active/Dead flags

# Performance Parameters (per aircraft)
var engine_factors: PackedFloat32Array = PackedFloat32Array()
var lift_factors: PackedFloat32Array = PackedFloat32Array()
var roll_authorities: PackedFloat32Array = PackedFloat32Array()

# AI Input Arrays
var input_pitches: PackedFloat32Array = PackedFloat32Array()
var input_rolls: PackedFloat32Array = PackedFloat32Array()
var input_yaws: PackedFloat32Array = PackedFloat32Array()

# Sub-Systems
var _render_system: MassRenderSystem
var _physics_engine: MassPhysicsEngine
var spatial_grid: SpatialGrid

# Constants
const MAX_AIRCRAFT: int = 2000

# Aircraft parameters (shared by all)
@export var max_speed: float = 50.0
@export var min_speed: float = 10.0
@export var acceleration: float = 20.0
@export var drag_factor: float = 0.01
@export var lift_factor: float = 0.5
@export var pitch_speed: float = 2.0
@export var roll_speed: float = 3.0
@export var pitch_acceleration: float = 5.0
@export var roll_acceleration: float = 5.0

# Stats
var active_count: int = 0
var ally_count: int = 0
var enemy_count: int = 0

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _ready() -> void:
	_initialize_arrays()
	
	# Initialize Sub-systems
	spatial_grid = SpatialGrid.new()
	spatial_grid.name = "SpatialGrid"
	add_child(spatial_grid)

	_render_system = MassRenderSystem.new()
	_render_system.name = "MassRenderSystem"
	add_child(_render_system)
	_render_system.initialize(self, MAX_AIRCRAFT)
	
	_physics_engine = MassPhysicsEngine.new()
	_physics_engine.name = "MassPhysicsEngine"
	add_child(_physics_engine)
	_physics_engine.initialize(self, MAX_AIRCRAFT)
	
	print("[MassAircraftSystem] Initialized with modular systems")

func _initialize_arrays() -> void:
	positions.resize(MAX_AIRCRAFT)
	velocities.resize(MAX_AIRCRAFT)
	rotations.resize(MAX_AIRCRAFT)
	speeds.resize(MAX_AIRCRAFT)
	throttles.resize(MAX_AIRCRAFT)
	healths.resize(MAX_AIRCRAFT)
	teams.resize(MAX_AIRCRAFT)
	states.resize(MAX_AIRCRAFT)
	
	engine_factors.resize(MAX_AIRCRAFT)
	lift_factors.resize(MAX_AIRCRAFT)
	roll_authorities.resize(MAX_AIRCRAFT)
	
	input_pitches.resize(MAX_AIRCRAFT)
	input_rolls.resize(MAX_AIRCRAFT)
	input_yaws.resize(MAX_AIRCRAFT)
	
	# Initialize all as inactive
	for i in range(MAX_AIRCRAFT):
		states[i] = 0  # 0 = inactive, 1 = active

func spawn_aircraft(pos: Vector3, team: int, initial_rotation: Vector3 = Vector3.ZERO) -> int:
	# Find inactive slot
	for i in range(MAX_AIRCRAFT):
		if states[i] == 0:
			positions[i] = pos
			velocities[i] = Vector3.ZERO
			rotations[i] = initial_rotation
			speeds[i] = min_speed
			throttles[i] = 0.5
			healths[i] = 100.0
			teams[i] = team
			states[i] = 1  # Active
			
			# Default performance
			engine_factors[i] = 1.0
			lift_factors[i] = 1.0
			roll_authorities[i] = 1.0
			
			# Default AI inputs
			input_pitches[i] = 0.0
			input_rolls[i] = 0.0
			input_yaws[i] = 0.0
			
			active_count += 1
			if team == GlobalEnums.Team.ALLY:
				ally_count += 1
			elif team == GlobalEnums.Team.ENEMY:
				enemy_count += 1
			
			return i
	
	push_warning("[MassAircraftSystem] Max aircraft limit reached!")
	return -1

func destroy_aircraft(index: int) -> void:
	if index < 0 or index >= MAX_AIRCRAFT:
		return
	
	if states[index] == 1:
		var team = teams[index]
		states[index] = 0  # Inactive
		active_count -= 1
		
		if team == GlobalEnums.Team.ALLY:
			ally_count -= 1
		elif team == GlobalEnums.Team.ENEMY:
			enemy_count -= 1

func damage_aircraft(index: int, amount: float) -> void:
	if index < 0 or index >= MAX_AIRCRAFT or states[index] == 0:
		return

	healths[index] -= amount
	if healths[index] <= 0:
		destroy_aircraft(index)

func get_aircraft_position(index: int) -> Vector3:
	if index < 0 or index >= MAX_AIRCRAFT or states[index] == 0:
		return Vector3.ZERO
	return positions[index]

func get_aircraft_team(index: int) -> int:
	if index < 0 or index >= MAX_AIRCRAFT or states[index] == 0:
		return GlobalEnums.Team.NEUTRAL
	return teams[index]

func _physics_process(delta: float) -> void:
	if active_count == 0:
		if _render_system:
			_render_system.hide_all()
		return
	
	if _physics_engine:
		_physics_engine.update_physics(delta)
	
	_update_spatial_grid()

	if _render_system:
		_render_system.update_rendering()

func _update_spatial_grid() -> void:
	spatial_grid.clear()
	# Only iterate if we have a reasonable number, or maybe every few frames?
	# For now, every frame to ensure accurate targeting/collision
	for i in range(MAX_AIRCRAFT):
		if states[i] == 1:
			spatial_grid.insert(i, positions[i])