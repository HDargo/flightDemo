extends CharacterBody3D
class_name GroundVehicle

signal vehicle_destroyed(vehicle: GroundVehicle)
signal health_changed(current: float, max: float)

enum VehicleType { TANK, APC, ARTILLERY, AA_GUN }

@export var vehicle_type: VehicleType = VehicleType.TANK
@export var faction: GlobalEnums.Team = GlobalEnums.Team.ENEMY
@export var max_speed: float = 20.0
@export var acceleration: float = 5.0
@export var turn_speed: float = 1.5
@export var max_health: float = 200.0
@export var turret_rotation_speed: float = 2.0
@export var max_turret_angle: float = 180.0
@export var min_barrel_pitch: float = -10.0 # Down
@export var max_barrel_pitch: float = 60.0  # Up

var current_health: float
var current_speed: float = 0.0
var target_speed: float = 0.0
var turn_input: float = 0.0
var is_alive: bool = true

@onready var visual_mesh: Node3D = $Visual if has_node("Visual") else null
@onready var turret: Node3D = $Visual/Turret if has_node("Visual/Turret") else null
@onready var barrel: Node3D = $Visual/Turret/Barrel if has_node("Visual/Turret/Barrel") else null
@onready var weapon_system: Node = $WeaponSystem if has_node("WeaponSystem") else null
@onready var collision_shape: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null

func _ready() -> void:
	current_health = max_health
	add_to_group("ground_vehicles")
	add_to_group("ally_ground" if faction == GlobalEnums.Team.ALLY else "enemy_ground")
	
	if weapon_system and weapon_system.has_method("set_faction"):
		weapon_system.set_faction(faction)
	
	_update_visual_color()

func _update_visual_color() -> void:
	var color = Color(0.2, 0.4, 1.0) # Blue for Ally
	if faction == GlobalEnums.Team.ENEMY:
		color = Color(1.0, 0.2, 0.2) # Red for Enemy
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	
	var hull_mesh = get_node_or_null("Visual/Hull")
	if hull_mesh and hull_mesh.has_method("set_surface_override_material"):
		hull_mesh.set_surface_override_material(0, mat)
		
	var turret_mesh = get_node_or_null("Visual/Turret/TurretMesh")
	if turret_mesh and turret_mesh.has_method("set_surface_override_material"):
		turret_mesh.set_surface_override_material(0, mat)
	
	# Path updated to BarrelMesh
	var barrel_mesh = get_node_or_null("Visual/Turret/Barrel/BarrelMesh")
	if barrel_mesh and barrel_mesh.has_method("set_surface_override_material"):
		barrel_mesh.set_surface_override_material(0, mat)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	# Rotation
	if abs(turn_input) > 0.01:
		rotate_y(turn_input * turn_speed * delta)
	
	# Movement
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

func set_turn_input(value: float) -> void:
	if not is_alive:
		return
	turn_input = clamp(value, -1.0, 1.0)

func aim_turret_at(target_position: Vector3, delta: float) -> void:
	if not turret or not is_alive:
		return
	
	# --- Ballistic Calculation ---
	var proj_speed = 80.0
	if weapon_system and "primary_speed" in weapon_system:
		proj_speed = weapon_system.primary_speed
	
	var dist_global = barrel.global_position.distance_to(target_position)
	if dist_global < 1.0: return
	
	var gravity = 4.9
	var time = dist_global / proj_speed
	var drop = 0.5 * gravity * time * time
	
	var aim_point = target_position + Vector3(0, drop, 0)
	
	# --- 1. Turret Yaw ---
	# Calculate target in local space of the tank body to handle hull rotation correctly
	# We use the aim_point (which includes gravity drop compensation) for yaw as well
	# This ensures we aim at the correct azimuth even for high-arcing shots
	var local_target = to_local(aim_point)
	var target_yaw = atan2(local_target.x, -local_target.z)
	
	# Use move_toward for constant mechanical speed (radians per second)
	var yaw_step = turret_rotation_speed * delta
	turret.rotation.y = move_toward(turret.rotation.y, target_yaw, yaw_step)

	# --- 2. Barrel Pitch ---
	if barrel:
		# Calculate direction to aim point
		var aim_dir = (aim_point - barrel.global_position).normalized()
		
		# We need the pitch relative to the TURRET, not the world.
		# Transform aim_dir into Turret's local space
		var local_aim_dir = turret.global_transform.basis.inverse() * aim_dir
		
		# Calculate pitch (rotation around X axis)
		# In Godot, -Z is forward. Pitch up is positive X? No, usually positive X is nose down?
		# Let's check standard: Basis.looking_at(dir)
		# If dir is (0, 1, 0) [UP], rotation is 90 deg on X.
		# atan2(y, -z) gives pitch.
		var target_pitch = atan2(local_aim_dir.y, -local_aim_dir.z)
		
		# Clamp Pitch
		# Note: Ensure min/max match the model's mechanical limits
		# Usually negative is UP in Godot if +X is Right? No.
		# Godot: X axis is Right. Rotation +X is "nose up" or "nose down"?
		# Right Hand Rule on X (Right): Thumb Right, Fingers curl Y(Up) -> Z(Back).
		# +X rotation moves Y towards Z. So +X is "Pitch Up" (nose points back/up?).
		# Wait, standard Godot LookAt: -Z is forward.
		# If I rotate +X (Right axis), the -Z vector moves towards -Y (Down).
		# So +X is PITCH DOWN. -X is PITCH UP.
		# Let's respect the exported variables min/max assuming they are degrees.
		# If min is -10 (Down?) and max is 60 (Up?), then in Godot terms:
		# Up (-X) = -60 deg. Down (+X) = +10 deg.
		# Let's assume the user provided friendly numbers: -10 (Down) to 60 (Up).
		# We need to invert or map them correctly.
		# Actually, let's just trust the clamp values provided are consistent with the model's rigging.
		# If previously it dug into ground, maybe -10 was "down into ground".
		
		var min_rad = deg_to_rad(min_barrel_pitch)
		var max_rad = deg_to_rad(max_barrel_pitch)
		
		# If rigging is standard (-Z forward), target_pitch is derived from atan2(y, -z).
		# If Y is positive (up), target_pitch is positive.
		# Wait, atan2(1, 0) = PI/2.
		# So Target Up = Positive Pitch.
		# If +X rotation means Pitch Down (see above), we have a mismatch.
		# Let's rely on how `Basis.looking_at` works, which was used before.
		# Before: target_pitch = desired_local_basis.get_euler().x
		# Let's stick to get_euler().x from a local basis to be safe, but apply smooth move.
		
		var desired_barrel_basis = Basis.looking_at(aim_dir, Vector3.UP)
		var relative_basis = turret.global_transform.basis.inverse() * desired_barrel_basis
		var calculated_pitch = relative_basis.get_euler().x
		
		calculated_pitch = clamp(calculated_pitch, deg_to_rad(min_barrel_pitch), deg_to_rad(max_barrel_pitch))
		
		barrel.rotation.x = move_toward(barrel.rotation.x, calculated_pitch, turret_rotation_speed * delta)

func fire_weapon(weapon_type: String = "primary") -> void:
	if weapon_system and weapon_system.has_method("fire"):
		weapon_system.fire(weapon_type)

func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, _attacker_faction: GlobalEnums.Team = GlobalEnums.Team.NEUTRAL) -> void:
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
		collision_shape.set_deferred("disabled", true)
	
	queue_free()

func get_faction() -> GlobalEnums.Team:
	return faction

func get_health_percentage() -> float:
	return current_health / max_health if max_health > 0 else 0.0

func is_aimed_at(target_pos: Vector3, tolerance_degrees: float = 5.0) -> bool:
	if not turret:
		return false
	
	# Check Yaw Alignment ONLY
	# (Pitch will inherently deviate due to ballistic arc, so checking strict vector alignment fails)
	
	var turret_fwd_flat = -turret.global_transform.basis.z
	turret_fwd_flat.y = 0
	turret_fwd_flat = turret_fwd_flat.normalized()
	
	var target_dir_flat = (target_pos - turret.global_position)
	target_dir_flat.y = 0
	target_dir_flat = target_dir_flat.normalized()
	
	var angle_diff = turret_fwd_flat.angle_to(target_dir_flat)
	return rad_to_deg(angle_diff) < tolerance_degrees
