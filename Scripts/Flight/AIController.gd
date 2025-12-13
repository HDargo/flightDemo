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
	
	# Initialize AI with default throttle to prevent immediate falling
	aircraft.throttle = 0.7  # Start at 70% throttle
	aircraft.input_throttle_up = true  # Begin accelerating
	
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
		
	# Optimize: Only search for target periodically
	if not is_instance_valid(target):
		target_search_timer -= delta
		if target_search_timer <= 0:
			find_target(my_data)
			# Reset timer with random jitter to prevent lag spikes
			target_search_timer = target_search_interval + randf_range(0.0, 0.5)
	
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
			fly_straight()
		GlobalEnums.AIState.CHASE:
			fly_towards_target(delta, my_data, target_data)
		GlobalEnums.AIState.ATTACK:
			fly_towards_target(delta, my_data, target_data)
			aircraft.input_fire = true
		GlobalEnums.AIState.EVADE:
			evade_target(delta)

	# Ground Avoidance Override
	if my_data.pos.y < 30.0:
		aircraft.input_pitch = 1.0
		aircraft.input_roll = 0.0 # Level wings
		aircraft.input_throttle_up = true # Max power

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
	aircraft.input_throttle_up = true # Maintain speed
	aircraft.input_fire = false

func evade_target(delta: float) -> void:
	# Break away! Pull up and roll randomly
	evade_timer -= delta
	if evade_timer <= 0:
		evade_timer = randf_range(1.0, 3.0)
		evade_roll_dir = randf_range(-1.0, 1.0)
		
	aircraft.input_pitch = 1.0 
	aircraft.input_roll = evade_roll_dir
	aircraft.input_throttle_up = true
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
	# Roll/Yaw error: Positive if target is to the right (local right)
	var yaw_error = direction_to_target.dot(my_basis.x)
	
	# Control inputs (PID-like)
	aircraft.input_pitch = clamp(pitch_error * 5.0, -1.0, 1.0)
	aircraft.input_roll = clamp(yaw_error * 5.0, -1.0, 1.0)
	
	manage_throttle(dist, my_data)

func manage_throttle(dist_to_target: float, my_data: Dictionary) -> void:
	var desired_throttle = 1.0
	
	# 1. Distance Check (Speed matching)
	if dist_to_target < min_distance * 3.0:
		desired_throttle = 0.6
	if dist_to_target < min_distance:
		desired_throttle = 0.0 # Cut throttle to avoid overshoot
		
	# 2. Energy Retention in Turns
	# If we are pulling Gs (high pitch input), we need power to sustain turn
	if abs(aircraft.input_pitch) > 0.5:
		desired_throttle = 1.0
		
	# 3. Climbing vs Diving
	var forward = -aircraft.global_transform.basis.z
	if forward.y > 0.2: # Climbing
		desired_throttle = 1.0
	elif forward.y < -0.5 and dist_to_target < 500.0: # Diving and close
		desired_throttle = 0.2
		
	# 4. Stall Prevention (Critical Override)
	# Use cached velocity for thread safety
	var current_speed = 0.0
	if not my_data.is_empty():
		current_speed = my_data.vel.length()
	
	if current_speed < aircraft.min_speed * 1.5:
		desired_throttle = 1.0
		
	# Apply inputs
	# We need a small deadzone or hysteresis to prevent jitter, but simple comparison is fine for now
	if aircraft.throttle < desired_throttle - 0.05:
		aircraft.input_throttle_up = true
		aircraft.input_throttle_down = false
	elif aircraft.throttle > desired_throttle + 0.05:
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = true
	else:
		aircraft.input_throttle_up = false
		aircraft.input_throttle_down = false
