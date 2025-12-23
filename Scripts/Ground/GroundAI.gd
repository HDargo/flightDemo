extends Node
class_name GroundAI

enum AIState { IDLE, PATROL, ENGAGE, RETREAT }

@export var detection_range: float = 500.0
@export var engagement_range: float = 300.0
@export var patrol_waypoints: Array[Vector3] = []
@export var patrol_speed: float = 10.0
@export var combat_speed: float = 5.0
@export var update_interval: float = 0.5
@export var operational_radius: float = 2000.0

var current_state: AIState = AIState.IDLE
var current_target: Node3D = null
var current_waypoint_index: int = 0
var update_timer: float = 0.0
var target_aim_position: Vector3 = Vector3.ZERO # For smooth aiming

@onready var vehicle: GroundVehicle = get_parent() as GroundVehicle

func _ready() -> void:
	if patrol_waypoints.size() > 0:
		current_state = AIState.PATROL

func _physics_process(delta: float) -> void:
	if not vehicle or not vehicle.is_alive:
		return
	
	# Smooth aiming update every frame
	if current_state == AIState.ENGAGE and is_instance_valid(current_target):
		var target_pos = current_target.global_position + Vector3(0, 1.5, 0) # Aim at center mass
		
		# Lead Prediction
		var dist = vehicle.global_position.distance_to(target_pos)
		var proj_speed = 80.0 # Approximate shell speed
		var time_to_hit = dist / proj_speed
		
		var target_vel = Vector3.ZERO
		if "velocity" in current_target:
			target_vel = current_target.velocity
		elif current_target is RigidBody3D:
			target_vel = current_target.linear_velocity
		
		target_aim_position = target_pos + (target_vel * time_to_hit)
		vehicle.aim_turret_at(target_aim_position, delta)
	elif current_state == AIState.PATROL:
		# Aim forward while patrolling
		var forward_point = vehicle.to_global(Vector3(0, 0, -50))
		target_aim_position = forward_point
		vehicle.aim_turret_at(target_aim_position, delta)
	
	update_timer += delta
	if update_timer < update_interval:
		return
	update_timer = 0.0
	
	# Boundary Check: If too far, force return to center
	var dist_from_center = Vector3(vehicle.global_position.x, 0, vehicle.global_position.z).length()
	if dist_from_center > operational_radius:
		_process_return_to_center(delta)
		return
	
	match current_state:
		AIState.IDLE:
			_process_idle()
		AIState.PATROL:
			_process_patrol(delta)
		AIState.ENGAGE:
			_process_engage(delta)
		AIState.RETREAT:
			_process_retreat(delta)

func _process_return_to_center(delta: float) -> void:
	# Ignore enemies and just drive towards center
	var direction_to_center = (Vector3.ZERO - vehicle.global_position).normalized()
	var vehicle_forward = -vehicle.global_transform.basis.z
	var angle = vehicle_forward.signed_angle_to(direction_to_center, Vector3.UP)
	
	_apply_steering(angle)
	vehicle.set_target_speed(vehicle.max_speed)

func _process_idle() -> void:
	vehicle.set_target_speed(0.0)
	_scan_for_enemies()

func _process_patrol(delta: float) -> void:
	if patrol_waypoints.size() == 0:
		current_state = AIState.IDLE
		return
	
	_scan_for_enemies()
	
	# If state changed to ENGAGE, stop patrol logic immediately
	if current_state != AIState.PATROL:
		return
	
	var target_pos = patrol_waypoints[current_waypoint_index]
	var distance = vehicle.global_position.distance_to(target_pos)
	
	if distance < 5.0:
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
		return
	
	var direction_to_waypoint = (target_pos - vehicle.global_position).normalized()
	var vehicle_forward = -vehicle.global_transform.basis.z
	
	var angle_to_target = vehicle_forward.signed_angle_to(direction_to_waypoint, Vector3.UP)
	
	_apply_steering(angle_to_target)
	
	vehicle.set_target_speed(patrol_speed)
	
	# Turret aiming is handled in _physics_process

func _process_engage(delta: float) -> void:
	if not is_instance_valid(current_target):
		current_target = null
		current_state = AIState.PATROL if patrol_waypoints.size() > 0 else AIState.IDLE
		return
	
	var distance = vehicle.global_position.distance_to(current_target.global_position)
	
	if distance > detection_range:
		current_target = null
		current_state = AIState.PATROL if patrol_waypoints.size() > 0 else AIState.IDLE
		return
	
	var direction_to_target = (current_target.global_position - vehicle.global_position).normalized()
	var vehicle_forward = -vehicle.global_transform.basis.z
	var angle_to_target = vehicle_forward.signed_angle_to(direction_to_target, Vector3.UP)
	
	_apply_steering(angle_to_target)
	
	if distance > engagement_range * 0.7:
		vehicle.set_target_speed(combat_speed)
	else:
		vehicle.set_target_speed(0.0)
	
	# Turret aiming is handled in _physics_process
	
	if distance <= engagement_range and vehicle.is_aimed_at(target_aim_position, 5.0):
		var is_aircraft = current_target.is_in_group("enemy_aircraft") or current_target.is_in_group("ally_aircraft")
		if is_aircraft:
			vehicle.fire_weapon("secondary")
		else:
			vehicle.fire_weapon("primary")

func _process_retreat(delta: float) -> void:
	if vehicle.get_health_percentage() > 0.3:
		current_state = AIState.ENGAGE
		return
	
	if current_target and is_instance_valid(current_target):
		var direction_away = (vehicle.global_position - current_target.global_position).normalized()
		var vehicle_forward = -vehicle.global_transform.basis.z
		var angle = vehicle_forward.signed_angle_to(direction_away, Vector3.UP)
		
		_apply_steering(angle)
		vehicle.set_target_speed(vehicle.max_speed)

func _apply_steering(angle: float) -> void:
	# Smooth proportional steering with deadzone
	if abs(angle) < 0.05:
		vehicle.set_turn_input(0.0)
	else:
		# Clamp input to -1.0 to 1.0
		# Gain of 3.0 means full turn at ~20 degrees (0.33 rad)
		vehicle.set_turn_input(clamp(angle * 3.0, -1.0, 1.0))

func _scan_for_enemies() -> void:
	# Sticky Target Logic: Keep current target if valid and in range
	if is_instance_valid(current_target):
		var dist = vehicle.global_position.distance_to(current_target.global_position)
		if dist <= detection_range:
			return # Keep locking on this target
	
	# Determine groups based on faction
	var ground_enemy_group = "enemy_ground" if vehicle.faction == GlobalEnums.Team.ALLY else "ally_ground"
	var air_enemy_group = "enemy_aircraft" if vehicle.faction == GlobalEnums.Team.ALLY else "ally_aircraft"
	
	var best_target: Node3D = null
	var min_dist: float = detection_range
	
	# Priority 1: Ground Enemies
	var ground_enemies = get_tree().get_nodes_in_group(ground_enemy_group)
	for enemy in ground_enemies:
		if not is_instance_valid(enemy): continue
		var dist = vehicle.global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			best_target = enemy
	
	# If ground target found, Engage!
	if best_target:
		current_target = best_target
		current_state = AIState.ENGAGE
		return
		
	# Priority 2: Aircraft Enemies (Only if no ground target found)
	var air_enemies = get_tree().get_nodes_in_group(air_enemy_group)
	for enemy in air_enemies:
		if not is_instance_valid(enemy): continue
		var dist = vehicle.global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			best_target = enemy
			
	if best_target:
		current_target = best_target
		current_state = AIState.ENGAGE

func set_waypoints(waypoints: Array[Vector3]) -> void:
	patrol_waypoints = waypoints
	current_waypoint_index = 0
	if waypoints.size() > 0:
		current_state = AIState.PATROL
