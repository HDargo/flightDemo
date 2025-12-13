extends CharacterBody3D
class_name GroundVehicle

signal vehicle_destroyed(vehicle: GroundVehicle)
signal health_changed(current: float, max: float)

enum VehicleType { TANK, APC, ARTILLERY, AA_GUN }

@export var vehicle_type: VehicleType = VehicleType.TANK
@export var faction: GlobalEnums.Faction = GlobalEnums.Faction.ENEMY
@export var max_speed: float = 20.0
@export var acceleration: float = 5.0
@export var turn_speed: float = 1.5
@export var max_health: float = 200.0
@export var turret_rotation_speed: float = 2.0
@export var max_turret_angle: float = 180.0

var current_health: float
var current_speed: float = 0.0
var target_speed: float = 0.0
var is_alive: bool = true

@onready var visual_mesh: Node3D = $Visual if has_node("Visual") else null
@onready var turret: Node3D = $Visual/Turret if has_node("Visual/Turret") else null
@onready var weapon_system: Node = $WeaponSystem if has_node("WeaponSystem") else null
@onready var collision_shape: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null

func _ready() -> void:
	current_health = max_health
	add_to_group("ground_vehicles")
	add_to_group("ally_ground" if faction == GlobalEnums.Faction.ALLY else "enemy_ground")
	
	if weapon_system and weapon_system.has_method("set_faction"):
		weapon_system.set_faction(faction)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	current_speed = lerp(current_speed, target_speed, acceleration * delta)
	
	velocity.x = -transform.basis.z.x * current_speed
	velocity.z = -transform.basis.z.z * current_speed
	
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = -1.0
	
	move_and_slide()

func set_target_speed(speed: float) -> void:
	target_speed = clamp(speed, -max_speed * 0.5, max_speed)

func turn(direction: float, delta: float) -> void:
	if not is_alive:
		return
	rotate_y(direction * turn_speed * delta)

func aim_turret_at(target_position: Vector3, delta: float) -> void:
	if not turret or not is_alive:
		return
	
	var local_target = to_local(target_position)
	var angle = atan2(local_target.x, local_target.z)
	
	if abs(rad_to_deg(angle)) <= max_turret_angle:
		var target_rotation = Vector3(0, angle, 0)
		turret.rotation.y = lerp_angle(turret.rotation.y, angle, turret_rotation_speed * delta)

func fire_weapon() -> void:
	if weapon_system and weapon_system.has_method("fire"):
		weapon_system.fire()

func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, _attacker_faction: GlobalEnums.Faction = GlobalEnums.Faction.NEUTRAL) -> void:
	if not is_alive:
		return
	
	current_health -= amount
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		_die()

func _die() -> void:
	is_alive = false
	vehicle_destroyed.emit(self)
	
	set_physics_process(false)
	
	if collision_shape:
		collision_shape.disabled = true
	
	queue_free()

func get_faction() -> GlobalEnums.Faction:
	return faction

func get_health_percentage() -> float:
	return current_health / max_health if max_health > 0 else 0.0
