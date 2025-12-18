extends Node

class_name AIController

@export var detection_radius: float = 1000.0
@export var attack_range: float = 500.0
@export var min_distance: float = 100.0 # Distance to break off

var aircraft: Aircraft
var target: Node3D
var state: int = GlobalEnums.AIState.IDLE

# Optimization: Cache IDs to avoid redundant object checks
var my_id: int = -1
var target_id: int = -1
var my_aircraft_index: int = -1  # Cache aircraft index to avoid find()

var evade_timer: float = 0.0
var evade_roll_dir: float = 1.0
var target_search_timer: float = 0.0
var target_search_interval: float = 2.0  # Increased from 1.0 for better performance

func _enter_tree() -> void:
	if FlightManager.instance:
		FlightManager.instance.register_ai(self)

func _exit_tree() -> void:
	if FlightManager.instance:
		FlightManager.instance.unregister_ai(self)

func _ready() -> void:
	set_physics_process(false)
	
	if not FlightManager.instance:
		await get_tree().process_frame
		if FlightManager.instance:
			FlightManager.instance.register_ai(self)
			
	aircraft = get_parent() as Aircraft
	if not aircraft:
		return
	
	# Initialize AI with safe throttle to prevent stalling
	aircraft.throttle = 0.8  # Start at 80% throttle (safe cruise speed)
	aircraft.input_throttle_up = false  # Don't accelerate immediately
	
	my_id = aircraft.get_instance_id()
	
	# Cache aircraft index for fast lookup
	if FlightManager.instance:
		my_aircraft_index = FlightManager.instance.aircrafts.find(aircraft)
	
	# Randomize initialization delay to spread out CPU load (0-3 seconds)
	var initialization_delay = randf_range(0.0, 3.0)
	await get_tree().create_timer(initialization_delay).timeout
	
	# Randomize initial search timer to spread out CPU load
	target_search_timer = randf_range(0.0, 1.0)

func process_ai(delta: float) -> void:
	if not is_instance_valid(aircraft):
		queue_free()
		return
	
	# Get my data from cache (Thread Safe)
	var my_data = FlightManager.instance.get_aircraft_data_by_id(my_id)
	if my_data.is_empty():
		return # Not registered yet or error

	# --- TERRAIN AWARENESS (SIMPLIFIED & AGGRESSIVE) ---
	# Clear rules: Speed first, then altitude
	
	if my_data.pos.y < 350.0:
		var altitude = my_data.pos.y
		var current_speed = my_data.vel.length()
		var forward_y = -aircraft.global_transform.basis.z.y
		
		# Speed thresholds
		var critical_speed = aircraft.min_speed * 1.8  # 18.0 m/s
		var safe_speed = aircraft.max_speed * 0.75     # 37.5 m/s
		
		# Calculate avoidance strength
		var avoidance_strength = 0.0
		if altitude < 80.0:
			avoidance_strength = 1.0
		else:
			avoidance_strength = 1.0 - ((altitude - 80.0) / 270.0)
		
		if forward_y < -0.15:  # Diving
			avoidance_strength += 0.5
			
		avoidance_strength = clamp(avoidance_strength, 0.0, 1.0)
		
		if avoidance_strength > 0.03:
			# Always max throttle in danger
			aircraft.input_throttle_up = true
			aircraft.input_throttle_down = false
			
			# CRITICAL: Level wings aggressively
			# Get current roll angle from basis
			var right = aircraft.global_transform.basis.x
			var roll_angle = atan2(right.y, right.length())  # Approximate roll
			
			# Counter-roll to level wings
			if abs(roll_angle) > 0.1:  # More than ~6 degrees
				aircraft.input_roll = -sign(roll_angle) * min(abs(roll_angle) * 3.0, 1.0)
			else:
				aircraft.input_roll = 0.0
			
			# PITCH CONTROL - Simple and effective
			var speed_factor = 0.0
			if current_speed < critical_speed:
				# TOO SLOW - Emergency dive
				aircraft.input_pitch = -0.8
			else:
				# Speed OK - Calculate safe pitch based on speed and altitude
				speed_factor = clamp((current_speed - critical_speed) / (safe_speed - critical_speed), 0.0, 1.0)
			# Base pitch increases with altitude danger (reduced due to better lift)
			var base_pitch = 0.3 + (avoidance_strength * 0.4)  # 0.3 to 0.7 (less aggressive needed)
			# Scale by speed - slow = less pitch
			var target_pitch = base_pitch * (0.35 + 0.65 * speed_factor)  # Min 35% (reduced from 40%)
			# Extra aggressive at very low altitude
			if altitude < 120.0 and current_speed > safe_speed * 0.8:
				target_pitch = min(target_pitch + 0.25, 0.9)  # Cap at 0.9 (was 1.0)
			aircraft.input_pitch = target_pitch
			aircraft.input_fire = false
		return # Priority control
	# ------------------------------------
	
	# IDLE STATE: Basic flight maintenance (prevent doing nothing)
	if state == GlobalEnums.AIState.IDLE:
		# Maintain altitude and speed even when no target
		var altitude = my_data.pos.y
		var current_speed = my_data.vel.length()
		
		# Keep wings level
		var right = aircraft.global_transform.basis.x
		var roll_angle = atan2(right.y, right.length())
		if abs(roll_angle) > 0.05:
			aircraft.input_roll = -sign(roll_angle) * 0.5
		else:
			aircraft.input_roll = 0.0
		
		# Maintain reasonable altitude (200m+)
		if altitude < 200.0:
			aircraft.input_pitch = 0.3  # Gentle climb
			aircraft.input_throttle_up = true
			aircraft.input_throttle_down = false
		elif altitude > 400.0:
			aircraft.input_pitch = -0.1  # Gentle descent
		else:
			aircraft.input_pitch = 0.0  # Level flight
		
		# Maintain cruise speed
		var target_speed = aircraft.max_speed * 0.7
		if current_speed < target_speed * 0.9:
			aircraft.input_throttle_up = true
			aircraft.input_throttle_down = false
		elif current_speed > target_speed * 1.1:
			aircraft.input_throttle_up = false
			aircraft.input_throttle_down = true
		else:
			aircraft.input_throttle_up = false
			aircraft.input_throttle_down = false
	
	var target_data: Dictionary = {}
	if is_instance_valid(target):
		target_data = FlightManager.instance.get_aircraft_data_by_id(target_id)
		if target_data.is_empty():
			target = null # Target lost/died
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
	
	match state:
		GlobalEnums.AIState.IDLE:
			# If too far, return to center
			if my_data.pos.length_squared() > 9000000.0: # 3000m^2
				var center_target = { "pos": Vector3.ZERO, "vel": Vector3.ZERO }
				fly_towards_target(delta, my_data, center_target)
			else:
				fly_straight()
		GlobalEnums.AIState.CHASE:
			fly_towards_target(delta, my_data, target_data)
		GlobalEnums.AIState.ATTACK:
			fly_towards_target(delta, my_data, target_data)
			aircraft.input_fire = true
		GlobalEnums.AIState.EVADE:
			evade_target(delta)

func find_target(my_data: Dictionary) -> void:
	if is_instance_valid(target):
		return
	
	# Use Spatial Grid for fast proximity search
	if not FlightManager.instance or not FlightManager.instance.spatial_grid:
		return
	
	var nearby_indices = FlightManager.instance.spatial_grid.query_nearby(
		my_data.pos,
		detection_radius
	)
	
	if nearby_indices.size() == 0:
		return
	
	var closest_dist_sq = detection_radius * detection_radius
	target = null
	target_id = -1
	
	# Check only nearby aircraft (spatial optimization)
	for idx in nearby_indices:
		if idx < 0 or idx >= FlightManager.instance.aircrafts.size():
			continue
		
		var other_aircraft = FlightManager.instance.aircrafts[idx]
		if not is_instance_valid(other_aircraft):
			continue
		
		# Skip same team
		if other_aircraft.team == my_data.team:
			continue
		
		# Skip self
		var other_id = other_aircraft.get_instance_id()
		if other_id == my_data.id:
			continue
		
		var other_data = FlightManager.instance.get_aircraft_data_by_id(other_id)
		if other_data.is_empty():
			continue
		
		var dist_sq = my_data.pos.distance_squared_to(other_data.pos)
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			target = other_aircraft
			target_id = other_id

func fly_straight() -> void:
	aircraft.input_pitch = 0.0
	aircraft.input_roll = 0.0
	aircraft.input_fire = false
	
	# Maintain safe cruise speed (increased from 0.75 to 0.8)
	var current_speed = aircraft.velocity.length()
	var target_speed = aircraft.max_speed * 0.8  # 40.0 for better lift
	
	if current_speed < target_speed * 0.9:
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
	elif current_speed > target_speed * 1.1:
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = true
	else:
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = false

func evade_target(delta: float) -> void:
	# Break away! Pull up and roll randomly
	evade_timer -= delta
	if evade_timer <= 0:
		evade_timer = randf_range(1.0, 3.0)
		evade_roll_dir = randf_range(-1.0, 1.0)
	
	# Check speed to prevent stall during evasion
	var current_speed = aircraft.velocity.length()
	var stall_speed = aircraft.min_speed * 1.5  # 15.0
	
	if current_speed < stall_speed * 1.2:  # Too slow for aggressive evasion
		# Prioritize speed recovery
		aircraft.input_pitch = 0.0  # Level off or slight nose down
		aircraft.input_roll = 0.0  # Wings level
	else:
		# Normal evasive maneuver
		aircraft.input_pitch = 1.0 
		aircraft.input_roll = evade_roll_dir
	
	aircraft.input_throttle_up = true
	aircraft.input_throttle_down = false
	aircraft.input_fire = false

func fly_towards_target(_delta: float, my_data: Dictionary, target_data: Dictionary) -> void:
	if target_data.is_empty():
		return
	
	# Pursuit with Prediction
	var my_pos = my_data.pos
	var target_pos = target_data.pos
	
	# Calculate vector to target once
	var to_target = target_pos - my_pos
	var dist_sq = to_target.length_squared()
	
	if dist_sq < 1.0: return # Too close
	
	var dist = sqrt(dist_sq)
	
	# Predict target position
	# time_to_hit = dist / 200.0 (Projectile Speed) -> dist * 0.005
	var time_to_hit = dist * 0.005
	
	# Calculate direction to predicted position directly
	# predicted_pos = target_pos + target_vel * time
	# dir = (predicted_pos - my_pos).normalized()
	#     = (target_pos - my_pos + target_vel * time).normalized()
	#     = (to_target + target_vel * time).normalized()
	var direction_to_target = (to_target + target_data.vel * time_to_hit).normalized()
	
	var my_basis = my_data.transform.basis
	
	# Pitch error: Positive if target is above (local up)
	var pitch_error = direction_to_target.dot(my_basis.y)
	
	# SAFETY: Don't dive if we are already low
	if my_data.pos.y < 250.0 and pitch_error < 0:
		# If target is below us and we are low, reduce pitch down authority
		# The lower we are, the less we are allowed to pitch down
		var limit = clamp((my_data.pos.y - 120.0) / 130.0, 0.0, 1.0) # 0.0 at 120m, 1.0 at 250m
		if pitch_error < -limit * 0.5:
			pitch_error = -limit * 0.5
			
	# Roll/Yaw error: Positive if target is to the right (local right)
	var yaw_error = direction_to_target.dot(my_basis.x)
	
	# Get current speed for stall prevention
	var current_speed = my_data.vel.length()
	var stall_speed = aircraft.min_speed * 1.5  # 15.0
	
	# STALL PREVENTION: Limit pitch input at low speeds
	if current_speed < stall_speed * 1.3:  # Below 19.5 m/s
		# Reduce pitch authority when slow
		var speed_factor = current_speed / (stall_speed * 1.3)  # 0.0 to 1.0
		var max_pitch = lerp(0.3, 1.0, speed_factor)  # 0.3 when stalling, 1.0 when fast
		pitch_error = clamp(pitch_error, -1.0, max_pitch)
		
		# If critically slow, force nose down
		if current_speed < stall_speed:
			pitch_error = min(pitch_error, -0.2)  # Force slight nose down
	
	# Control inputs (PID-like)
	aircraft.input_pitch = clamp(pitch_error * 5.0, -1.0, 1.0)
	aircraft.input_roll = clamp(yaw_error * 5.0, -1.0, 1.0)
	
	manage_throttle(dist, my_data)

func manage_throttle(dist_to_target: float, my_data: Dictionary) -> void:
	# Get current speed from velocity
	var current_speed = 0.0
	if not my_data.is_empty():
		current_speed = my_data.vel.length()
	
	# Get altitude for safety checks
	var altitude = my_data.pos.y if not my_data.is_empty() else 200.0
	
	# Target optimal cruise speed (80% of max_speed for better lift)
	var target_speed = aircraft.max_speed * 0.8  # 40.0 for max_speed=50
	var stall_speed = aircraft.min_speed * 1.5     # 15.0 for min_speed=10 (safety margin)
	
	var desired_throttle = 0.75  # Default cruise throttle
	
	# CRITICAL: LOW ALTITUDE OVERRIDE - Never reduce throttle below certain altitude
	if altitude < 200.0:
		desired_throttle = max(desired_throttle, 0.8)  # Minimum 80% throttle at low altitude
	
	# 1. CRITICAL: Stall Prevention (Highest Priority)
	if current_speed < stall_speed:
		desired_throttle = 1.0  # Full throttle to recover
	elif current_speed < target_speed * 0.8:  # Below cruise speed
		desired_throttle = max(desired_throttle, 0.9)  # High throttle to accelerate
	
	# 2. Climbing (Energy intensive - needs more power)
	var forward = -aircraft.global_transform.basis.z
	if forward.y > 0.15:  # Climbing
		desired_throttle = min(desired_throttle + 0.2, 1.0)
	
	# 3. High G Maneuvers (Pulling hard - bleed speed fast)
	if abs(aircraft.input_pitch) > 0.6 or abs(aircraft.input_roll) > 0.6:
		desired_throttle = min(desired_throttle + 0.15, 1.0)
	
	# 4. Combat Distance Management (ONLY at safe altitude)
	if altitude > 200.0:  # Only manage distance throttle when safe
		if dist_to_target < min_distance * 0.8:
			desired_throttle = max(desired_throttle - 0.15, 0.7)  # Gentle reduction
		elif dist_to_target > attack_range * 1.5:
			desired_throttle = min(desired_throttle + 0.1, 1.0)  # Chase harder
	
	# 5. Overspeed Control (only reduce if way too fast AND at safe altitude)
	if current_speed > aircraft.max_speed * 0.95 and altitude > 200.0:
		var forward_y = forward.y
		if forward_y < -0.5:  # Steep dive
			desired_throttle = max(0.5, desired_throttle - 0.2)  # Reduce but not too much
		else:
			desired_throttle = max(desired_throttle - 0.1, 0.6)
	
	# Apply throttle inputs with hysteresis to prevent oscillation
	var throttle_threshold = 0.08
	if aircraft.throttle < desired_throttle - throttle_threshold:
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
	elif aircraft.throttle > desired_throttle + throttle_threshold:
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = true
	else:
		# Within deadzone - maintain current throttle
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = false
