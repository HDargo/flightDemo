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
var target_search_interval: float = 0.5 # Increased frequency for better reaction

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
	set_physics_process(true) # Enable per-frame input application
	
	if not FlightManager.instance:
		await get_tree().process_frame
		if FlightManager.instance:
			FlightManager.instance.register_ai(self)
			
	aircraft = get_parent() as Aircraft
	if not aircraft:
		return
	
	aircraft.throttle = 0.8
	my_id = aircraft.get_instance_id()
	
	if FlightManager.instance:
		my_aircraft_index = FlightManager.instance.aircrafts.find(aircraft)
	
	target_search_timer = randf_range(0.0, 1.0)

func _physics_process(delta: float) -> void:
	# Apply inputs every frame for smooth control, even if process_ai is called less often
	apply_inputs(delta)

func process_ai(delta: float) -> void:
	if not is_instance_valid(aircraft):
		queue_free()
		return
	
	var my_data = FlightManager.instance.get_aircraft_data_by_id(my_id)
	if my_data.is_empty():
		return

	# 1. Target Management
	target_search_timer -= delta
	if target_search_timer <= 0 or not is_instance_valid(target):
		target_search_timer = target_search_interval
		find_target(my_data)

	# 2. Critical Survival Logic (Stall & Terrain)
	# handle_survival now sets target_pitch/roll but doesn't necessarily block combat
	var in_danger = handle_survival(delta, my_data)

	# 3. Combat/Flight Logic
	var target_data: Dictionary = {}
	if is_instance_valid(target):
		target_data = FlightManager.instance.get_aircraft_data_by_id(target_id)
		if target_data.is_empty():
			target = null
			target_id = -1
			state = GlobalEnums.AIState.IDLE
		else:
			var dist_sq = my_data.pos.distance_squared_to(target_data.pos)
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
				if my_data.pos.length_squared() > 25000000.0: # 5km
					var center_target = {"pos": Vector3.ZERO, "vel": Vector3.ZERO}
					fly_towards_target(delta, my_data, center_target)
				else:
					maintain_flight(delta, my_data)
			GlobalEnums.AIState.CHASE, GlobalEnums.AIState.ATTACK:
				fly_towards_target(delta, my_data, target_data)
				aircraft.input_fire = (state == GlobalEnums.AIState.ATTACK)
			GlobalEnums.AIState.EVADE:
				evade_target(delta, my_data)
	else:
		# In danger, still allow firing if target is somewhat in front
		if is_instance_valid(target) and state == GlobalEnums.AIState.ATTACK:
			var forward = - aircraft.global_transform.basis.z
			var to_target = (target_data.pos - my_data.pos).normalized()
			aircraft.input_fire = forward.dot(to_target) > 0.9
		else:
			aircraft.input_fire = false

func handle_survival(delta: float, my_data: Dictionary) -> bool:
	var altitude = my_data.pos.y
	var vertical_speed = my_data.vel.y
	var current_speed = my_data.vel.length()
	var forward = - aircraft.global_transform.basis.z
	var current_pitch = asin(clamp(forward.y, -1.0, 1.0))
	
	# Predictive Ground Avoidance
	# If we are falling, we need more space to pull out
	var descent_rate = max(0.0, -vertical_speed)
	var time_to_impact = 999.0
	if descent_rate > 1.0:
		time_to_impact = altitude / descent_rate
	
	# Dynamic floor: The faster we fall, the earlier we must pull up
	# Base floor 150m, plus 4 seconds of current descent distance
	var safety_floor = 150.0 + (descent_rate * 4.0)
	
	# A. Critical Terrain Avoidance (Panic Pull)
	if altitude < safety_floor:
		var danger_factor = clamp(1.0 - (altitude / safety_floor), 0.0, 1.0)
		
		# If extremely low or about to impact, max priority
		if danger_factor > 0.1 or time_to_impact < 4.0:
			aircraft.input_throttle_up = true
			aircraft.input_throttle_down = false
			
			# Level wings first if we are banked too much, to maximize lift vector upwards
			var right = aircraft.global_transform.basis.x
			var up = aircraft.global_transform.basis.y
			var upright_dot = up.dot(Vector3.UP)
			
			# Roll Logic: Shortest path to upright
			# If Right Wing is High (right.y > 0), we want to Roll Right (+) to lower it.
			# If Right Wing is Low (right.y < 0), we want to Roll Left (-) to raise it.
			target_roll = clamp(right.y * 5.0, -1.0, 1.0)
			
			# Inverted Fix: If upside down, we can't be stable.
			# If up.y is negative (inverted) and right.y is small (wings "level" but inverted),
			# the proportional control above is too weak (right.y ~ 0).
			# We must FORCE a roll.
			if upright_dot < 0.0:
				var roll_dir = 1.0
				if right.y < 0.0: roll_dir = -1.0
				target_roll = roll_dir * 1.0
			
			# Pitch control: Gated by orientation
			# If we are banked heavily (> 60 deg) or inverted (upright_dot < 0.5), 
			# pulling UP (positive pitch) actually sends us sideways or down.
			if upright_dot < 0.5:
				# FOCUS ON ROLL. Do not pull up yet.
				# Neutral pitch or slight push to keep nose from dropping relative to horizon if possible,
				# but effectively just wait for roll.
				target_pitch = 0.0
			else:
				# We are upright enough that pulling back moves us away from ground
				if current_pitch > deg_to_rad(45.0):
					target_pitch = 0.5 # Maintain steep climb
				else:
					if time_to_impact < 2.0:
						target_pitch = 1.0
					else:
						target_pitch = clamp(danger_factor * 5.0 + 0.2, 0.2, 1.0)
			
			return true # Block other commands
	
	# B. Stall Recovery (Secondary Priority)
	if current_speed < aircraft.min_speed * 1.5:
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
		
		# Only dive to recover speed if we have altitude!
		if altitude > 400.0:
			target_pitch = -0.3 # Nose down to gain speed
		else:
			target_pitch = 0.0 # Level flight to minimize lift loss while accelerating
			
		target_roll = 0.0
		return true
			
	return false

func find_target(my_data: Dictionary) -> void:
	if not FlightManager.instance or not FlightManager.instance.spatial_grid:
		return
	
	var nearby_indices = FlightManager.instance.spatial_grid.query_nearby(my_data.pos, detection_radius)
	if nearby_indices.size() == 0:
		return
	
	var closest_dist_sq = detection_radius * detection_radius
	var best_target = null
	var best_id = -1
	
	for idx in nearby_indices:
		if idx < 0 or idx >= FlightManager.instance.aircrafts.size(): continue
		var other = FlightManager.instance.aircrafts[idx]
		if not is_instance_valid(other) or other.team == my_data.team: continue
		
		var other_id = other.get_instance_id()
		if other_id == my_id: continue
		
		var other_data = FlightManager.instance.get_aircraft_data_by_id(other_id)
		if other_data.is_empty(): continue
		
		var dist_sq = my_data.pos.distance_squared_to(other_data.pos)
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			best_target = other
			best_id = other_id
			
	if best_target:
		target = best_target
		target_id = best_id

func maintain_flight(delta: float, my_data: Dictionary) -> void:
	# Keep wings level and maintain altitude
	var right = aircraft.global_transform.basis.x
	var up = aircraft.global_transform.basis.y
	
	# Roll Logic:
	target_roll = clamp(right.y * 2.0, -1.0, 1.0)
	
	# Anti-Inverted Check:
	if up.y < 0.0:
		var roll_dir = 1.0
		if right.y < 0.0: roll_dir = -1.0
		target_roll = roll_dir * 1.0
	
	var altitude = my_data.pos.y
	var vertical_speed = my_data.vel.y
	
	# PID-like altitude hold
	var target_altitude = 400.0
	var error = target_altitude - altitude
	
	# If we are low, we want positive vertical speed
	# If we are high, we want negative vertical speed
	var desired_vs = clamp(error * 0.1, -20.0, 20.0)
	var vs_error = desired_vs - vertical_speed
	
	target_pitch = clamp(vs_error * 0.05, -0.5, 0.5)
	
	var speed = my_data.vel.length()
	var cruise_speed = aircraft.max_speed * 0.7
	aircraft.input_throttle_up = (speed < cruise_speed * 0.9)
	aircraft.input_throttle_down = (speed > cruise_speed * 1.1)
	aircraft.input_fire = false

func fly_towards_target(_delta: float, my_data: Dictionary, target_data: Dictionary) -> void:
	var to_target = target_data.pos - my_data.pos
	var dist = to_target.length()
	
	# 1. Lead Prediction (Synced with projectile speed ~200)
	var time_to_hit = dist / 200.0
	var predicted_pos = target_data.pos + target_data.vel * time_to_hit
	var dir = (predicted_pos - my_data.pos).normalized()
	
	var my_basis = aircraft.global_transform.basis
	
	# 2. Bank-to-Turn Logic
	# Calculate local errors
	var local_dir = my_basis.inverse() * dir
	
	# Yaw error for fine alignment
	target_yaw = clamp(local_dir.x * 2.0, -1.0, 1.0)
	
	# Roll to align lift vector with target
	# We want target to be in our local Y-Z plane (up-forward)
	var roll_error = atan2(local_dir.x, local_dir.y)
	target_roll = clamp(roll_error * 3.0, -1.0, 1.0)
	
	# Pitch to pull towards target
	# The more we are rolled towards the target, the more we pull
	var alignment = clamp(Vector2(local_dir.x, local_dir.y).normalized().y, 0.0, 1.0)
	target_pitch = clamp(local_dir.y * 5.0, -0.5, 1.0) * (0.5 + 0.5 * alignment)
	
	# 3. Throttle Management
	manage_throttle(dist, my_data)

func evade_target(delta: float, _my_data: Dictionary) -> void:
	evade_timer -= delta
	if evade_timer <= 0:
		evade_timer = randf_range(1.0, 2.5)
		evade_roll_dir = 1.0 if randf() > 0.5 else -1.0
	
	target_pitch = 0.8
	target_roll = evade_roll_dir
	aircraft.input_throttle_up = true
	aircraft.input_fire = false

func manage_throttle(dist: float, my_data: Dictionary) -> void:
	var speed = my_data.vel.length()
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
	# Smooth transitions to prevent jitter (Increased speed for responsiveness)
	var lerp_speed = clamp(15.0 * delta, 0.0, 1.0)
	aircraft.input_pitch = lerp(aircraft.input_pitch, target_pitch, lerp_speed)
	aircraft.input_roll = lerp(aircraft.input_roll, target_roll, lerp_speed)
	# Note: Aircraft.gd might not have input_yaw, but we set it just in case or for future use
	if "input_yaw" in aircraft:
		aircraft.input_yaw = lerp(aircraft.input_yaw, target_yaw, lerp_speed)
	
	# Clamp final values
	aircraft.input_pitch = clamp(aircraft.input_pitch, -1.0, 1.0)
	aircraft.input_roll = clamp(aircraft.input_roll, -1.0, 1.0)
