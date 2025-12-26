extends Node

class_name AIController

@export var detection_radius: float = 2500.0
@export var attack_range: float = 600.0
@export var min_distance: float = 120.0

var aircraft: Aircraft
var target: Node3D
var state: int = GlobalEnums.AIState.IDLE

# Optimization: Cache IDs to avoid redundant object checks
var my_id: int = -1
var target_id: int = -1
var my_aircraft_index: int = -1

var evade_timer: float = 0.0
var evade_roll_dir: float = 1.0
var target_search_timer: float = 0.0
var target_search_interval: float = 0.5 

# Smoothing for inputs
var target_pitch: float = 0.0
var target_roll: float = 0.0
var target_yaw: float = 0.0

func _enter_tree() -> void:
	if FlightManager.instance:
		FlightManager.instance.register_ai(self)

func _exit_tree() -> void:
	if FlightManager.instance:
		FlightManager.instance.unregister_ai(self)

func _ready() -> void:
	set_physics_process(true)
	
	if not FlightManager.instance:
		await get_tree().process_frame
		if FlightManager.instance:
			FlightManager.instance.register_ai(self)
			
	aircraft = get_parent() as Aircraft
	if not aircraft:
		return
	
	aircraft.throttle = 0.8
	my_id = aircraft.get_instance_id()
	target_search_timer = randf_range(0.0, 1.0)

func _physics_process(delta: float) -> void:
	apply_inputs(delta)

func process_ai(delta: float) -> void:
	if not is_instance_valid(aircraft):
		queue_free()
		return
	
	var my_pos = aircraft.global_position
	var my_vel = aircraft.velocity
	var my_team = aircraft.team

	# 1. Target Management
	target_search_timer -= delta
	if target_search_timer <= 0 or not is_instance_valid(target):
		target_search_timer = target_search_interval + randf_range(0, 0.2)
		var my_data_minimal = {"pos": my_pos, "team": my_team}
		find_target(my_data_minimal)

	# 2. Critical Survival Logic
	var my_data_survival = {"pos": my_pos, "vel": my_vel}
	var in_danger = handle_survival(delta, my_data_survival)

	# 3. Combat/Flight Logic
	var target_pos = Vector3.ZERO
	var target_vel = Vector3.ZERO
	
	if is_instance_valid(target):
		target_pos = target.global_position
		target_vel = target.velocity
		
		var dist_sq = my_pos.distance_squared_to(target_pos)
		if dist_sq < min_distance * min_distance:
			state = GlobalEnums.AIState.EVADE
		elif dist_sq < attack_range * attack_range:
			state = GlobalEnums.AIState.ATTACK
		else:
			state = GlobalEnums.AIState.CHASE
	else:
		state = GlobalEnums.AIState.IDLE

	# Only run combat logic if not in extreme danger
	if not in_danger:
		match state:
			GlobalEnums.AIState.IDLE:
				if my_pos.length_squared() > 25000000.0: # 5km
					fly_towards_target(delta, my_pos, Vector3.ZERO, Vector3.ZERO)
				else:
					maintain_flight(delta, my_pos, my_vel)
			GlobalEnums.AIState.CHASE, GlobalEnums.AIState.ATTACK:
				fly_towards_target(delta, my_pos, target_pos, target_vel)
				aircraft.input_fire = (state == GlobalEnums.AIState.ATTACK)
			GlobalEnums.AIState.EVADE:
				evade_target(delta)
	else:
		if is_instance_valid(target) and state == GlobalEnums.AIState.ATTACK:
			var forward = - aircraft.global_transform.basis.z
			var to_target = (target_pos - my_pos).normalized()
			aircraft.input_fire = forward.dot(to_target) > 0.9
		else:
			aircraft.input_fire = false

func handle_survival(delta: float, my_data: Dictionary) -> bool:
	var altitude = my_data.pos.y
	var vertical_speed = my_data.vel.y
	var current_speed = my_data.vel.length()
	var forward = - aircraft.global_transform.basis.z
	var current_pitch = asin(clamp(forward.y, -1.0, 1.0))
	
	var horizontal_pos = Vector2(my_data.pos.x, my_data.pos.z)
	var dist_from_center = horizontal_pos.length()
	var max_operational_radius = 4500.0
	
	if dist_from_center > max_operational_radius:
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
		var dir_to_center = (Vector3.ZERO - my_data.pos).normalized()
		var my_basis = aircraft.global_transform.basis
		var local_dir = my_basis.inverse() * dir_to_center
		target_roll = clamp(atan2(local_dir.x, local_dir.y) * 3.0, -1.0, 1.0)
		target_pitch = clamp(local_dir.y * 5.0, -0.3, 0.5)
		return true

	var descent_rate = max(0.0, -vertical_speed)
	var time_to_impact = 999.0
	if descent_rate > 1.0:
		time_to_impact = altitude / descent_rate
	
	var safety_floor = 150.0 + (descent_rate * 4.0)
	
	if altitude < safety_floor:
		var danger_factor = clamp(1.0 - (altitude / safety_floor), 0.0, 1.0)
		
		# More aggressive ground avoidance
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
		
		var right = aircraft.global_transform.basis.x
		var up = aircraft.global_transform.basis.y
		var upright_dot = up.dot(Vector3.UP)
		
		# Level wings faster
		target_roll = clamp(right.y * 10.0, -1.0, 1.0)
		
		# If we are dangerously low, pull up even if not perfectly level
		if upright_dot > 0.3: # Banked up to ~72 degrees is OK to pull back
			target_pitch = clamp(danger_factor * 8.0 + 0.5, 0.5, 1.0)
		else:
			# If inverted or heavily banked, just focus on rolling
			target_pitch = 0.0
			
		return true
	
	if current_speed < aircraft.min_speed * 1.5:
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
		if altitude > 400.0:
			target_pitch = -0.3
		else:
			target_pitch = 0.0
		target_roll = 0.0
		return true
	return false

func find_target(my_data: Dictionary) -> void:
	if not FlightManager.instance or not FlightManager.instance.spatial_grid:
		return
	var nearby_indices = FlightManager.instance.spatial_grid.query_nearby(my_data.pos, detection_radius)
	if nearby_indices.size() == 0: return
	
	var closest_dist_sq = detection_radius * detection_radius
	var best_target = null
	var best_id = -1
	var my_team = my_data.team
	var all_aircrafts = FlightManager.instance.cached_aircrafts
	var list_size = all_aircrafts.size()
	
	for idx in nearby_indices:
		if idx < 0 or idx >= list_size: continue
		var other = all_aircrafts[idx]
		if not is_instance_valid(other) or other.team == my_team: continue
		var other_id = other.get_instance_id()
		if other_id == my_id: continue
		var dist_sq = my_data.pos.distance_squared_to(other.global_position)
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			best_target = other
			best_id = other_id
	if best_target:
		target = best_target
		target_id = best_id

func maintain_flight(delta: float, my_pos: Vector3, my_vel: Vector3) -> void:
	var right = aircraft.global_transform.basis.x
	var up = aircraft.global_transform.basis.y
	target_roll = clamp(right.y * 2.0, -1.0, 1.0)
	if up.y < 0.0:
		target_roll = (1.0 if right.y < 0.0 else -1.0)
	
	var altitude = my_pos.y
	var vertical_speed = my_vel.y
	var target_altitude = 400.0
	var error = target_altitude - altitude
	var desired_vs = clamp(error * 0.1, -20.0, 20.0)
	var vs_error = desired_vs - vertical_speed
	target_pitch = clamp(vs_error * 0.05, -0.5, 0.5)
	
	var speed = my_vel.length()
	var cruise_speed = aircraft.max_speed * 0.7
	aircraft.input_throttle_up = (speed < cruise_speed * 0.9)
	aircraft.input_throttle_down = (speed > cruise_speed * 1.1)
	aircraft.input_fire = false

func fly_towards_target(_delta: float, my_pos: Vector3, t_pos: Vector3, t_vel: Vector3) -> void:
	var to_target = t_pos - my_pos
	var dist = to_target.length()
	var time_to_hit = dist / 200.0
	var predicted_pos = t_pos + t_vel * time_to_hit
	var dir = (predicted_pos - my_pos).normalized()
	var my_basis = aircraft.global_transform.basis
	var local_dir = my_basis.inverse() * dir
	target_yaw = clamp(local_dir.x * 2.0, -1.0, 1.0)
	var roll_error = atan2(local_dir.x, local_dir.y)
	target_roll = clamp(roll_error * 3.0, -1.0, 1.0)
	var alignment = clamp(Vector2(local_dir.x, local_dir.y).normalized().y, 0.0, 1.0)
	target_pitch = clamp(local_dir.y * 5.0, -0.5, 1.0) * (0.5 + 0.5 * alignment)
	manage_throttle(dist, my_pos, t_pos)

func evade_target(delta: float) -> void:
	evade_timer -= delta
	if evade_timer <= 0:
		evade_timer = randf_range(1.0, 2.5)
		evade_roll_dir = 1.0 if randf() > 0.5 else -1.0
	target_pitch = 0.8
	target_roll = evade_roll_dir
	aircraft.input_throttle_up = true
	aircraft.input_fire = false

func manage_throttle(dist: float, my_pos: Vector3, t_pos: Vector3) -> void:
	var speed = aircraft.velocity.length()
	var target_speed = aircraft.max_speed * 0.85
	if dist < min_distance * 1.5:
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = true
	elif speed < target_speed:
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
	else:
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = false

func apply_inputs(delta: float) -> void:
	var lerp_speed = clamp(15.0 * delta, 0.0, 1.0)
	aircraft.input_pitch = lerp(aircraft.input_pitch, target_pitch, lerp_speed)
	aircraft.input_roll = lerp(aircraft.input_roll, target_roll, lerp_speed)
	if "input_yaw" in aircraft:
		aircraft.input_yaw = lerp(aircraft.input_yaw, target_yaw, lerp_speed)
	aircraft.input_pitch = clamp(aircraft.input_pitch, -1.0, 1.0)
	aircraft.input_roll = clamp(aircraft.input_roll, -1.0, 1.0)
