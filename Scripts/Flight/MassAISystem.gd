extends Node

class_name MassAISystem

## Efficient AI system for 1000+ aircraft using batch processing

# AI States per aircraft
var ai_states: PackedInt32Array = PackedInt32Array()  # AIState enum
var ai_targets: PackedInt32Array = PackedInt32Array()  # Target index (-1 = none)
var ai_timers: PackedFloat32Array = PackedFloat32Array()  # For periodic updates

# AI Output (to be applied to MassAircraftSystem inputs)
var ai_pitch_outputs: PackedFloat32Array = PackedFloat32Array()
var ai_roll_outputs: PackedFloat32Array = PackedFloat32Array()
var ai_throttle_outputs: PackedFloat32Array = PackedFloat32Array()
var ai_fire_outputs: PackedInt32Array = PackedInt32Array()  # 0 or 1

# Performance settings
const AI_UPDATE_INTERVAL: float = 0.2  # Update every 0.2 seconds
const DETECTION_RADIUS_SQ: float = 1000000.0  # 1000m
const ATTACK_RANGE_SQ: float = 250000.0  # 500m
const MIN_DISTANCE_SQ: float = 10000.0  # 100m

# Thread pool
var _ai_task_group_id: int = -1
var _thread_count: int = 4

func _ready() -> void:
	_thread_count = max(1, OS.get_processor_count() - 1)

func initialize(max_aircraft: int) -> void:
	ai_states.resize(max_aircraft)
	ai_targets.resize(max_aircraft)
	ai_timers.resize(max_aircraft)
	
	ai_pitch_outputs.resize(max_aircraft)
	ai_roll_outputs.resize(max_aircraft)
	ai_throttle_outputs.resize(max_aircraft)
	ai_fire_outputs.resize(max_aircraft)
	
	# Initialize all to idle
	for i in range(max_aircraft):
		ai_states[i] = GlobalEnums.AIState.IDLE
		ai_targets[i] = -1
		ai_timers[i] = randf_range(0.0, AI_UPDATE_INTERVAL)  # Stagger updates
		ai_throttle_outputs[i] = 0.5

func process_ai_batch(delta: float, mass_system: MassAircraftSystem, camera_pos: Vector3) -> void:
	# Wait for previous tasks
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
	
	# Count active aircraft
	var active_count = 0
	for i in range(mass_system.states.size()):
		if mass_system.states[i] == 1:
			active_count += 1
	
	if active_count == 0:
		return
	
	# Dispatch threaded AI processing
	_ai_task_group_id = WorkerThreadPool.add_group_task(
		_process_ai_thread.bind(delta, mass_system, camera_pos, active_count),
		_thread_count,
		-1,
		true,
		"Mass AI Processing"
	)

func _process_ai_thread(task_idx: int, delta: float, mass_system: MassAircraftSystem, camera_pos: Vector3, total_active: int) -> void:
	var max_aircraft = mass_system.states.size()
	var start_idx = int(float(task_idx * max_aircraft) / _thread_count)
	var end_idx = int(float((task_idx + 1) * max_aircraft) / _thread_count)
	
	for i in range(start_idx, end_idx):
		if mass_system.states[i] == 0:
			continue
		
		# Update timer
		ai_timers[i] -= delta
		
		# Distance-based update frequency
		var dist_sq = camera_pos.distance_squared_to(mass_system.positions[i])
		var update_interval = AI_UPDATE_INTERVAL
		
		if dist_sq > 4000000.0:  # > 2km
			update_interval = AI_UPDATE_INTERVAL * 4.0
		elif dist_sq > 1000000.0:  # > 1km
			update_interval = AI_UPDATE_INTERVAL * 2.0
		
		# Only process if timer expired
		if ai_timers[i] > 0.0:
			continue
		
		ai_timers[i] = update_interval
		
		# AI Logic
		_process_single_ai(i, mass_system)

func _process_single_ai(index: int, mass_system: MassAircraftSystem) -> void:
	var my_pos = mass_system.positions[index]
	var my_team = mass_system.teams[index]
	
	# Find target if none
	if ai_targets[index] == -1:
		ai_targets[index] = _find_nearest_enemy(index, my_pos, my_team, mass_system)
	
	# Check if target still valid
	var target_idx = ai_targets[index]
	if target_idx != -1:
		if mass_system.states[target_idx] == 0:
			# Target dead
			ai_targets[index] = -1
			ai_states[index] = GlobalEnums.AIState.IDLE
			return
		
		var target_pos = mass_system.positions[target_idx]
		var dist_sq = my_pos.distance_squared_to(target_pos)
		
		# Update state based on distance
		if dist_sq < MIN_DISTANCE_SQ:
			ai_states[index] = GlobalEnums.AIState.EVADE
		elif dist_sq < ATTACK_RANGE_SQ:
			ai_states[index] = GlobalEnums.AIState.ATTACK
		else:
			ai_states[index] = GlobalEnums.AIState.CHASE
		
		# Generate control inputs
		_generate_control_inputs(index, target_idx, mass_system)
	else:
		ai_states[index] = GlobalEnums.AIState.IDLE
		_generate_idle_inputs(index)

func _find_nearest_enemy(index: int, pos: Vector3, team: int, mass_system: MassAircraftSystem) -> int:
	var nearest_idx = -1
	var nearest_dist_sq = DETECTION_RADIUS_SQ
	
	for i in range(mass_system.states.size()):
		if mass_system.states[i] == 0 or i == index:
			continue
		
		if mass_system.teams[i] == team:
			continue  # Same team
		
		var dist_sq = pos.distance_squared_to(mass_system.positions[i])
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest_idx = i
	
	return nearest_idx

func _generate_control_inputs(index: int, target_idx: int, mass_system: MassAircraftSystem) -> void:
	var my_pos = mass_system.positions[index]
	var my_rot = mass_system.rotations[index]
	
	# Altitude Check (Ground Avoidance)
	var altitude = my_pos.y
	var is_low = altitude < 250.0
	var is_critical = altitude < 120.0
	
	if is_critical:
		# PANIC: Pull up hard, level wings, max throttle
		
		var my_basis = Basis.from_euler(my_rot)
		var right = my_basis.x
		var local_up = my_basis.y
		var upright_dot = local_up.dot(Vector3.UP)
		
		# Pitch Logic: Only pull up if upright
		if upright_dot < 0.5:
			ai_pitch_outputs[index] = 0.0
		else:
			ai_pitch_outputs[index] = 1.0
			
		# Level wings: Roll towards 0 (Right wing high -> Roll Right to lower it)
		# Note: Right.y > 0 means Bank Left (Right wing is UP).
		# To fix, we roll Right (+).
		ai_roll_outputs[index] = clamp(right.y * 5.0, -1.0, 1.0)
		
		# Inverted Fix:
		if upright_dot < 0.0:
			var roll_dir = 1.0
			if right.y < 0.0: roll_dir = -1.0
			ai_roll_outputs[index] = roll_dir * 1.0
			
		ai_throttle_outputs[index] = 1.0
		ai_fire_outputs[index] = 0
		return # Override all other logic
	
	var target_pos = mass_system.positions[target_idx]
	var my_basis = Basis.from_euler(my_rot)
	var my_forward = -my_basis.z
	
	var to_target = (target_pos - my_pos).normalized()
	
	match ai_states[index]:
		GlobalEnums.AIState.CHASE, GlobalEnums.AIState.ATTACK:
			# Point towards target
			var dot_forward = my_forward.dot(to_target)
			var right = my_basis.x
			var dot_right = right.dot(to_target)
			var dot_up = my_basis.y.dot(to_target)
			
			# Pitch control
			var pitch_input = -dot_up
			
			# Safety: If low and target is below, don't dive
			if is_low and target_pos.y < my_pos.y:
				pitch_input = max(pitch_input, 0.1) # Maintain slight climb
				
			ai_pitch_outputs[index] = pitch_input
			
			# Roll control
			ai_roll_outputs[index] = dot_right
			
			# Throttle
			if dot_forward > 0.7:
				ai_throttle_outputs[index] = 0.8  # Full speed when aligned
			else:
				ai_throttle_outputs[index] = 0.5  # Slow down to turn
			
			# Fire
			if ai_states[index] == GlobalEnums.AIState.ATTACK and dot_forward > 0.95:
				ai_fire_outputs[index] = 1
			else:
				ai_fire_outputs[index] = 0
		
		GlobalEnums.AIState.EVADE:
			# Evade: Roll and turn away
			ai_pitch_outputs[index] = 0.5  # Pull up harder
			ai_roll_outputs[index] = 1.0 if randf() > 0.5 else -1.0  # Hard roll
			ai_throttle_outputs[index] = 1.0  # Full throttle
			ai_fire_outputs[index] = 0
		
		_:
			_generate_idle_inputs(index)

func _generate_idle_inputs(index: int) -> void:
	# Keep safe altitude even in idle
	ai_pitch_outputs[index] = 0.1 # Slight climb
	ai_roll_outputs[index] = 0.0
	ai_throttle_outputs[index] = 0.6
	ai_fire_outputs[index] = 0

func apply_ai_to_mass_system(mass_system: MassAircraftSystem) -> void:
	# Apply AI outputs to MassAircraftSystem inputs
	for i in range(mass_system.states.size()):
		if mass_system.states[i] == 0:
			continue
		
		mass_system.input_pitches[i] = ai_pitch_outputs[i]
		mass_system.input_rolls[i] = ai_roll_outputs[i]
		mass_system.throttles[i] = ai_throttle_outputs[i]
		
		# Handle firing separately if needed
		# TODO: Integrate weapon system

