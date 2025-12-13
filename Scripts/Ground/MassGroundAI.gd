extends Node
class_name MassGroundAI

## AI system for mass ground vehicles

var _ground_system: MassGroundSystem

# AI Targets
var _target_indices: PackedInt32Array = PackedInt32Array()
var _target_update_timers: PackedFloat32Array = PackedFloat32Array()
const TARGET_UPDATE_INTERVAL: float = 2.0

# Pathfinding
var _waypoints: Array[PackedVector3Array] = []

func initialize(max_count: int) -> void:
	_target_indices.resize(max_count)
	_target_update_timers.resize(max_count)
	_waypoints.resize(max_count)
	
	for i in max_count:
		_target_indices[i] = -1
		_target_update_timers[i] = randf_range(0, TARGET_UPDATE_INTERVAL)

func set_ground_system(system: MassGroundSystem) -> void:
	_ground_system = system

func _physics_process(delta: float) -> void:
	if not _ground_system:
		return
	
	_update_ai(delta)

func _update_ai(delta: float) -> void:
	for i in _ground_system.active_count:
		if _ground_system.states[i] == 0:
			continue
		
		_target_update_timers[i] -= delta
		
		if _target_update_timers[i] <= 0:
			_target_update_timers[i] = TARGET_UPDATE_INTERVAL
			_find_target(i)
		
		_execute_ai_behavior(i, delta)

func _find_target(idx: int) -> void:
	var my_pos = _ground_system.positions[idx]
	var my_team = _ground_system.teams[idx]
	
	var closest_dist = INF
	var closest_idx = -1
	
	for j in _ground_system.active_count:
		if _ground_system.states[j] == 0:
			continue
		
		if _ground_system.teams[j] == my_team:
			continue
		
		var dist = my_pos.distance_squared_to(_ground_system.positions[j])
		
		if dist < closest_dist:
			closest_dist = dist
			closest_idx = j
	
	_target_indices[idx] = closest_idx

func _execute_ai_behavior(idx: int, delta: float) -> void:
	var target_idx = _target_indices[idx]
	
	if target_idx == -1 or not _ground_system.is_vehicle_alive(target_idx):
		_ground_system.input_throttles[idx] = 0.5
		_ground_system.input_steers[idx] = 0.0
		return
	
	var my_pos = _ground_system.positions[idx]
	var my_rot = _ground_system.rotations[idx]
	var target_pos = _ground_system.positions[target_idx]
	
	var to_target = target_pos - my_pos
	to_target.y = 0
	to_target = to_target.normalized()
	
	var forward = Vector3(sin(my_rot.y), 0, cos(my_rot.y))
	
	var angle_diff = forward.signed_angle_to(to_target, Vector3.UP)
	
	_ground_system.input_steers[idx] = clamp(angle_diff * 2.0, -1.0, 1.0)
	
	var dist = my_pos.distance_to(target_pos)
	
	if dist > 50.0:
		_ground_system.input_throttles[idx] = 1.0
	elif dist > 30.0:
		_ground_system.input_throttles[idx] = 0.5
	else:
		_ground_system.input_throttles[idx] = 0.0
