extends Node
class_name GroundAI

enum AIState { IDLE, PATROL, ENGAGE, RETREAT }

@export var detection_range: float = 500.0
@export var engagement_range: float = 300.0
@export var patrol_waypoints: Array[Vector3] = []
@export var patrol_speed: float = 10.0
@export var combat_speed: float = 5.0
@export var update_interval: float = 0.5

var current_state: AIState = AIState.IDLE
var current_target: Node3D = null
var current_waypoint_index: int = 0
var update_timer: float = 0.0

@onready var vehicle: GroundVehicle = get_parent() as GroundVehicle

func _ready() -> void:
	if patrol_waypoints.size() > 0:
		current_state = AIState.PATROL

func _physics_process(delta: float) -> void:
	if not vehicle or not vehicle.is_alive:
		return
	
	update_timer += delta
	if update_timer < update_interval:
		return
	update_timer = 0.0
	
	match current_state:
		AIState.IDLE:
			_process_idle()
		AIState.PATROL:
			_process_patrol(delta)
		AIState.ENGAGE:
			_process_engage(delta)
		AIState.RETREAT:
			_process_retreat(delta)

func _process_idle() -> void:
	vehicle.set_target_speed(0.0)
	_scan_for_enemies()

func _process_patrol(delta: float) -> void:
	if patrol_waypoints.size() == 0:
		current_state = AIState.IDLE
		return
	
	_scan_for_enemies()
	
	var target_pos = patrol_waypoints[current_waypoint_index]
	var distance = vehicle.global_position.distance_to(target_pos)
	
	if distance < 5.0:
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
		return
	
	var direction_to_waypoint = (target_pos - vehicle.global_position).normalized()
	var vehicle_forward = -vehicle.global_transform.basis.z
	
	var angle_to_target = vehicle_forward.signed_angle_to(direction_to_waypoint, Vector3.UP)
	
	if abs(angle_to_target) > 0.1:
		vehicle.turn(sign(angle_to_target), update_interval)
	
	vehicle.set_target_speed(patrol_speed)

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
	
	if abs(angle_to_target) > 0.1:
		vehicle.turn(sign(angle_to_target), update_interval)
	
	if distance > engagement_range * 0.7:
		vehicle.set_target_speed(combat_speed)
	else:
		vehicle.set_target_speed(0.0)
	
	vehicle.aim_turret_at(current_target.global_position, update_interval)
	
	if distance <= engagement_range and abs(angle_to_target) < 0.3:
		vehicle.fire_weapon()

func _process_retreat(delta: float) -> void:
	if vehicle.get_health_percentage() > 0.3:
		current_state = AIState.ENGAGE
		return
	
	if current_target and is_instance_valid(current_target):
		var direction_away = (vehicle.global_position - current_target.global_position).normalized()
		var vehicle_forward = -vehicle.global_transform.basis.z
		var angle = vehicle_forward.signed_angle_to(direction_away, Vector3.UP)
		
		vehicle.turn(sign(angle), update_interval)
		vehicle.set_target_speed(vehicle.max_speed)

func _scan_for_enemies() -> void:
	var enemy_group = "enemy_aircraft" if vehicle.faction == GlobalEnums.Faction.ALLY else "ally_aircraft"
	var enemies = get_tree().get_nodes_in_group(enemy_group)
	
	var ground_enemy_group = "enemy_ground" if vehicle.faction == GlobalEnums.Faction.ALLY else "ally_ground"
	enemies.append_array(get_tree().get_nodes_in_group(ground_enemy_group))
	
	var closest_enemy: Node3D = null
	var closest_distance: float = detection_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		var distance = vehicle.global_position.distance_to(enemy.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_enemy = enemy
	
	if closest_enemy:
		current_target = closest_enemy
		current_state = AIState.ENGAGE

func set_waypoints(waypoints: Array[Vector3]) -> void:
	patrol_waypoints = waypoints
	current_waypoint_index = 0
	if waypoints.size() > 0:
		current_state = AIState.PATROL
