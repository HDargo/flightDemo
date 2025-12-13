extends Node
class_name GroundWeaponSystem

signal weapon_fired(projectile: Node3D)

@export var projectile_scene: PackedScene
@export var fire_rate: float = 1.0
@export var projectile_speed: float = 100.0
@export var projectile_damage: float = 25.0
@export var muzzle_velocity_spread: float = 2.0

var can_fire: bool = true
var faction: GlobalEnums.Faction = GlobalEnums.Faction.NEUTRAL

@onready var fire_point: Node3D = $FirePoint if has_node("FirePoint") else get_parent()
@onready var fire_timer: Timer = Timer.new()

func _ready() -> void:
	add_child(fire_timer)
	fire_timer.one_shot = true
	fire_timer.timeout.connect(_on_fire_timer_timeout)

func set_faction(new_faction: GlobalEnums.Faction) -> void:
	faction = new_faction

func fire() -> void:
	if not can_fire or not projectile_scene:
		return
	
	var projectile = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)
	
	projectile.global_position = fire_point.global_position
	projectile.global_rotation = fire_point.global_rotation
	
	if projectile.has_method("set_damage"):
		projectile.set_damage(projectile_damage)
	
	if projectile.has_method("set_faction"):
		projectile.set_faction(faction)
	
	if projectile is RigidBody3D:
		var direction = -fire_point.global_transform.basis.z
		var spread = Vector3(
			randf_range(-muzzle_velocity_spread, muzzle_velocity_spread),
			randf_range(-muzzle_velocity_spread, muzzle_velocity_spread),
			randf_range(-muzzle_velocity_spread, muzzle_velocity_spread)
		)
		projectile.linear_velocity = (direction + spread) * projectile_speed
	elif projectile.has_method("set_velocity"):
		var direction = -fire_point.global_transform.basis.z
		projectile.set_velocity(direction * projectile_speed)
	
	weapon_fired.emit(projectile)
	
	can_fire = false
	fire_timer.start(1.0 / fire_rate)

func _on_fire_timer_timeout() -> void:
	can_fire = true
