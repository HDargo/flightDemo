extends Node
class_name MassGroundSystem

## Large-scale ground vehicle simulation using PackedArrays and MultiMesh
## Handles 500+ ground vehicles efficiently

static var instance: MassGroundSystem

# Packed Arrays for CPU-side data
var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var rotations: PackedVector3Array = PackedVector3Array()  # Euler angles (Y rotation only for ground)
var speeds: PackedFloat32Array = PackedFloat32Array()
var throttles: PackedFloat32Array = PackedFloat32Array()
var healths: PackedFloat32Array = PackedFloat32Array()
var teams: PackedInt32Array = PackedInt32Array()
var states: PackedInt32Array = PackedInt32Array()  # Active/Dead flags
var vehicle_types: PackedInt32Array = PackedInt32Array()  # Tank, APC, etc.

# Performance Parameters
var move_speeds: PackedFloat32Array = PackedFloat32Array()
var turn_speeds: PackedFloat32Array = PackedFloat32Array()

# AI Input Arrays
var input_throttles: PackedFloat32Array = PackedFloat32Array()
var input_steers: PackedFloat32Array = PackedFloat32Array()

# Rendering (LOD support)
var _multimesh_ally_tank: MultiMeshInstance3D
var _multimesh_enemy_tank: MultiMeshInstance3D
var _multimesh_ally_apc: MultiMeshInstance3D
var _multimesh_enemy_apc: MultiMeshInstance3D

# LOD distance thresholds (squared)
const LOD_HIGH_DIST_SQ: float = 160000.0    # 400m
const LOD_MEDIUM_DIST_SQ: float = 1000000.0 # 1000m

# Constants
const MAX_VEHICLES: int = 500
const PHYSICS_FRAME_BUDGET_MS: float = 3.0

# Vehicle parameters
@export var max_speed: float = 20.0
@export var acceleration: float = 10.0
@export var turn_speed: float = 1.5
@export var drag_factor: float = 0.5

# Stats
var active_count: int = 0
var ally_count: int = 0
var enemy_count: int = 0

# Culling
var _camera: Camera3D
var _frustum_planes: Array[Plane] = []

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _ready() -> void:
	_initialize_arrays()
	_setup_multimesh()

func _initialize_arrays() -> void:
	positions.resize(MAX_VEHICLES)
	velocities.resize(MAX_VEHICLES)
	rotations.resize(MAX_VEHICLES)
	speeds.resize(MAX_VEHICLES)
	throttles.resize(MAX_VEHICLES)
	healths.resize(MAX_VEHICLES)
	teams.resize(MAX_VEHICLES)
	states.resize(MAX_VEHICLES)
	vehicle_types.resize(MAX_VEHICLES)
	
	move_speeds.resize(MAX_VEHICLES)
	turn_speeds.resize(MAX_VEHICLES)
	
	input_throttles.resize(MAX_VEHICLES)
	input_steers.resize(MAX_VEHICLES)
	
	for i in MAX_VEHICLES:
		states[i] = 0

func _setup_multimesh() -> void:
	var tank_mesh = _create_tank_mesh()
	var apc_mesh = _create_apc_mesh()
	
	_multimesh_ally_tank = _create_multimesh_instance(tank_mesh, "AllyTanks")
	_multimesh_enemy_tank = _create_multimesh_instance(tank_mesh, "EnemyTanks")
	_multimesh_ally_apc = _create_multimesh_instance(apc_mesh, "AllyAPCs")
	_multimesh_enemy_apc = _create_multimesh_instance(apc_mesh, "EnemyAPCs")
	
	add_child(_multimesh_ally_tank)
	add_child(_multimesh_enemy_tank)
	add_child(_multimesh_ally_apc)
	add_child(_multimesh_enemy_apc)

func _create_multimesh_instance(mesh: Mesh, name_prefix: String) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	mmi.name = name_prefix
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX_VEHICLES
	
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	return mmi

func _create_tank_mesh() -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(3, 2, 4)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.3, 0.3)
	mesh.material = material
	
	return mesh

func _create_apc_mesh() -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(2.5, 2.5, 5)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.4, 0.3)
	mesh.material = material
	
	return mesh

func _physics_process(delta: float) -> void:
	if active_count == 0:
		return
	
	_update_camera_frustum()
	_update_physics(delta)
	_update_rendering()

func _update_camera_frustum() -> void:
	if not _camera:
		_camera = get_viewport().get_camera_3d()
	
	if _camera:
		_frustum_planes = _camera.get_frustum()

func _update_physics(delta: float) -> void:
	var start_time = Time.get_ticks_usec()
	var budget_us = PHYSICS_FRAME_BUDGET_MS * 1000.0
	
	for i in active_count:
		if states[i] == 0:
			continue
		
		var elapsed = Time.get_ticks_usec() - start_time
		if elapsed > budget_us:
			break
		
		var pos = positions[i]
		var rot = rotations[i]
		var vel = velocities[i]
		var spd = speeds[i]
		
		var forward = Vector3(sin(rot.y), 0, cos(rot.y))
		
		var target_speed = input_throttles[i] * max_speed * move_speeds[i]
		spd = move_toward(spd, target_speed, acceleration * delta)
		
		var turn_input = input_steers[i]
		rot.y += turn_input * turn_speed * turn_speeds[i] * delta
		
		vel = forward * spd
		vel.y = -0.1
		pos += vel * delta
		
		pos.y = 0.0
		
		positions[i] = pos
		velocities[i] = vel
		rotations[i] = rot
		speeds[i] = spd

func _update_rendering() -> void:
	if not _camera:
		return
	
	var cam_pos = _camera.global_position
	
	var ally_tank_idx = 0
	var enemy_tank_idx = 0
	var ally_apc_idx = 0
	var enemy_apc_idx = 0
	
	for i in active_count:
		if states[i] == 0:
			continue
		
		var pos = positions[i]
		var rot = rotations[i]
		
		var dist_sq = cam_pos.distance_squared_to(pos)
		if dist_sq > LOD_MEDIUM_DIST_SQ:
			continue
		
		if not _is_in_frustum(pos):
			continue
		
		var transform = Transform3D()
		transform = transform.rotated(Vector3.UP, rot.y)
		transform.origin = pos
		
		var team = teams[i]
		var vtype = vehicle_types[i]
		
		if team == GlobalEnums.Team.ALLY:
			if vtype == 0:  # Tank
				if ally_tank_idx < _multimesh_ally_tank.multimesh.instance_count:
					_multimesh_ally_tank.multimesh.set_instance_transform(ally_tank_idx, transform)
					ally_tank_idx += 1
			else:  # APC
				if ally_apc_idx < _multimesh_ally_apc.multimesh.instance_count:
					_multimesh_ally_apc.multimesh.set_instance_transform(ally_apc_idx, transform)
					ally_apc_idx += 1
		else:
			if vtype == 0:  # Tank
				if enemy_tank_idx < _multimesh_enemy_tank.multimesh.instance_count:
					_multimesh_enemy_tank.multimesh.set_instance_transform(enemy_tank_idx, transform)
					enemy_tank_idx += 1
			else:  # APC
				if enemy_apc_idx < _multimesh_enemy_apc.multimesh.instance_count:
					_multimesh_enemy_apc.multimesh.set_instance_transform(enemy_apc_idx, transform)
					enemy_apc_idx += 1
	
	_multimesh_ally_tank.multimesh.visible_instance_count = ally_tank_idx
	_multimesh_enemy_tank.multimesh.visible_instance_count = enemy_tank_idx
	_multimesh_ally_apc.multimesh.visible_instance_count = ally_apc_idx
	_multimesh_enemy_apc.multimesh.visible_instance_count = enemy_apc_idx

func _is_in_frustum(pos: Vector3) -> bool:
	if _frustum_planes.is_empty():
		return true
	
	for plane in _frustum_planes:
		if plane.distance_to(pos) < -10.0:
			return false
	return true

func spawn_vehicle(pos: Vector3, faction: GlobalEnums.Team, vtype: int = 0) -> int:
	if active_count >= MAX_VEHICLES:
		return -1
	
	var idx = active_count
	active_count += 1
	
	positions[idx] = pos
	velocities[idx] = Vector3.ZERO
	rotations[idx] = Vector3(0, randf_range(0, TAU), 0)
	speeds[idx] = 0.0
	throttles[idx] = 0.0
	healths[idx] = 100.0
	teams[idx] = faction
	states[idx] = 1
	vehicle_types[idx] = vtype
	
	move_speeds[idx] = randf_range(0.8, 1.2)
	turn_speeds[idx] = randf_range(0.8, 1.2)
	
	input_throttles[idx] = 0.0
	input_steers[idx] = 0.0
	
	if faction == GlobalEnums.Team.ALLY:
		ally_count += 1
	else:
		enemy_count += 1
	
	return idx

func destroy_vehicle(idx: int) -> void:
	if idx < 0 or idx >= active_count:
		return
	
	if states[idx] == 0:
		return
	
	states[idx] = 0
	
	if teams[idx] == GlobalEnums.Team.ALLY:
		ally_count -= 1
	else:
		enemy_count -= 1

func get_vehicle_position(idx: int) -> Vector3:
	if idx >= 0 and idx < active_count:
		return positions[idx]
	return Vector3.ZERO

func get_vehicle_team(idx: int) -> GlobalEnums.Team:
	if idx >= 0 and idx < active_count:
		return teams[idx] as GlobalEnums.Team
	return GlobalEnums.Team.ALLY

func is_vehicle_alive(idx: int) -> bool:
	if idx >= 0 and idx < active_count:
		return states[idx] != 0
	return false

func damage_vehicle(idx: int, amount: float) -> void:
	if idx < 0 or idx >= active_count:
		return
	
	if states[idx] == 0:
		return
	
	healths[idx] -= amount
	
	if healths[idx] <= 0:
		destroy_vehicle(idx)
