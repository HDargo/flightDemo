extends Node
class_name GroundWeaponSystem

signal weapon_fired(projectile: Node3D, type: String)

# Primary Weapon (Anti-Ground / Heavy Cannon)
@export_group("Primary Weapon")
@export var primary_projectile: PackedScene
@export var primary_fire_rate: float = 0.5
@export var primary_speed: float = 80.0
@export var primary_damage: float = 50.0
@export var primary_spread: float = 0.02

# Secondary Weapon (Anti-Air / Machine Gun)
@export_group("Secondary Weapon")
@export var secondary_projectile: PackedScene
@export var secondary_fire_rate: float = 5.0
@export var secondary_speed: float = 150.0
@export var secondary_damage: float = 10.0
@export var secondary_spread: float = 0.1
@export var fire_point_primary_node: Node3D
@export var fire_point_secondary_node: Node3D

var can_fire_primary: bool = true
var can_fire_secondary: bool = true
var faction: GlobalEnums.Team = GlobalEnums.Team.NEUTRAL

var timer_primary: Timer
var timer_secondary: Timer

func _ready() -> void:
	timer_primary = Timer.new()
	timer_primary.one_shot = true
	timer_primary.timeout.connect(func(): can_fire_primary = true)
	add_child(timer_primary)
	
	timer_secondary = Timer.new()
	timer_secondary.one_shot = true
	timer_secondary.timeout.connect(func(): can_fire_secondary = true)
	add_child(timer_secondary)

func set_faction(new_faction: GlobalEnums.Team) -> void:
	faction = new_faction

func fire(weapon_type: String = "primary") -> void:
	# print("[Weapon] Firing ", weapon_type, " from ", get_parent().name) # Debug
	var projectile_scene: PackedScene
	var speed: float
	var damage: float
	var spread_amount: float
	var fire_point: Node3D
	
	if weapon_type == "primary":
		if not can_fire_primary: return
		projectile_scene = primary_projectile
		speed = primary_speed
		damage = primary_damage
		spread_amount = primary_spread
		fire_point = fire_point_primary_node
	else:
		if not can_fire_secondary: return
		projectile_scene = secondary_projectile
		speed = secondary_speed
		damage = secondary_damage
		spread_amount = secondary_spread
		fire_point = fire_point_secondary_node
		if not fire_point_secondary_node and fire_point_primary_node: # Fallback
			fire_point = fire_point_primary_node

	if not projectile_scene or not fire_point:
		return
	
	# Play Muzzle Flash
	var muzzle_flash = fire_point.get_node_or_null("MuzzleFlash")
	if muzzle_flash and muzzle_flash is GPUParticles3D:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	
	var projectile = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)
	
	projectile.global_position = fire_point.global_position
	projectile.global_rotation = fire_point.global_rotation
	
	if projectile.has_method("set_damage"):
		projectile.set_damage(damage)
	
	if projectile.has_method("set_faction"):
		projectile.set_faction(faction)
	
	if "shooter" in projectile:
		projectile.shooter = get_parent()
	
	if projectile is RigidBody3D:
		var direction = -fire_point.global_transform.basis.z
		var spread = Vector3(
			randf_range(-spread_amount, spread_amount),
			randf_range(-spread_amount, spread_amount),
			randf_range(-spread_amount, spread_amount)
		)
		projectile.linear_velocity = (direction + spread).normalized() * speed
	elif projectile.has_method("set_velocity"):
		var direction = -fire_point.global_transform.basis.z
		projectile.set_velocity(direction * speed)
	
	weapon_fired.emit(projectile, weapon_type)
	
	if weapon_type == "primary":
		can_fire_primary = false
		timer_primary.start(1.0 / primary_fire_rate)
	else:
		can_fire_secondary = false
		timer_secondary.start(1.0 / secondary_fire_rate)
