extends CharacterBody3D

class_name Aircraft

signal damage_taken(direction: Vector3)
signal physics_updated(speed: float, altitude: float, vertical_speed: float, aoa: float, stall_factor: float)

# Utility modules
const FlightPhysics = preload("res://Scripts/Flight/FlightPhysics.gd")
const DamageSystem = preload("res://Scripts/Flight/DamageSystem.gd")

# Components (NEW)
var input_handler: Node = null
var weapon_system: Node = null

# Settings
@export var max_speed: float = 50.0
@export var min_speed: float = 10.0  # Minimum flight speed to maintain lift
@export var acceleration: float = 60.0 # High thrust for arcade feel
@export var drag_factor: float = 0.006 # Balanced drag
@export var turn_speed: float = 2.0
@export var pitch_speed: float = 2.0
@export var roll_speed: float = 3.0
@export var pitch_acceleration: float = 5.0
@export var roll_acceleration: float = 5.0
@export var lift_factor: float = 0.00178  # Calculated: 0.0082 / 4.6 to normalize 464% lift to ~100%
@export var mouse_sensitivity: float = 0.002
@export var fire_rate: float = 0.1
@export var missile_lock_range: float = 2000.0
@export var team: GlobalEnums.Team = GlobalEnums.Team.NEUTRAL
@export var is_player: bool = true

var missile_scene = preload("res://Scenes/Entities/Missile.tscn")

# State
var current_speed: float = 0.0
var current_pitch: float = 0.0
var current_roll: float = 0.0
var throttle: float = 0.0 # 0.0 to 1.0
var input_pitch: float = 0.0
var input_roll: float = 0.0
var input_fire: bool = false
var input_missile: bool = false
var input_throttle_up: bool = false
var input_throttle_down: bool = false

var last_fire_time: float = 0.0
var last_missile_time: float = 0.0
var missile_cooldown: float = 2.0
var locked_target: Node3D = null
var _performance_dirty: bool = false

# Debug
var _last_debug_second: int = 0

# Wing damage and crash state
var _wing_destroyed: bool = false
var _spin_factor: float = 0.0
var _crash_timer: float = 0.0

# Damage System
var parts_health = {
	"nose": 50.0,
	"fuselage": 150.0,
	"engine": 100.0,
	"l_wing_in": 80.0,
	"l_wing_out": 60.0,
	"r_wing_in": 80.0,
	"r_wing_out": 60.0,
	"v_tail": 60.0,
	"h_tail": 60.0
}
var max_part_healths = {
	"nose": 50.0,
	"fuselage": 150.0,
	"engine": 100.0,
	"l_wing_in": 80.0,
	"l_wing_out": 60.0,
	"r_wing_in": 80.0,
	"r_wing_out": 60.0,
	"v_tail": 60.0,
	"h_tail": 60.0
}

# Cached Performance Factors (Optimization)
var _c_engine_factor: float = 1.0
var _c_lift_factor: float = 1.0
var _c_h_tail_factor: float = 1.0
var _c_v_tail_factor: float = 1.0
var _c_roll_authority: float = 1.0
var _c_wing_imbalance: float = 0.0

func recalculate_performance_factors() -> void:
	var factors = DamageSystem.calculate_performance_factors(parts_health, max_part_healths)
	
	_c_engine_factor = factors["engine_factor"]
	_c_lift_factor = factors["lift_factor"]
	_c_h_tail_factor = factors["h_tail_factor"]
	_c_v_tail_factor = factors["v_tail_factor"]
	_c_roll_authority = factors["roll_authority"]
	_c_wing_imbalance = factors["wing_imbalance"]

func _enter_tree() -> void:
	if FlightManager.instance:
		FlightManager.instance.register_aircraft(self)
		if is_player:
			print("[Aircraft] Player aircraft registered: ", get_instance_id())

func _exit_tree() -> void:
	# Cleanup weapon system threading
	if weapon_system and "_target_search_task_id" in weapon_system:
		var task_id = weapon_system._target_search_task_id
		if task_id != -1:
			WorkerThreadPool.wait_for_task_completion(task_id)
	
	if FlightManager.instance:
		FlightManager.instance.unregister_aircraft(self)

func _ready() -> void:
	# Physics process is enabled by default for CharacterBody3D
	
	# Setup components FIRST
	_setup_components()
	
	# Only register if not already registered in _enter_tree
	if not FlightManager.instance:
		await get_tree().process_frame
		if FlightManager.instance:
			FlightManager.instance.register_aircraft(self)
			if is_player:
				print("[Aircraft] Player aircraft registered (delayed): ", get_instance_id())
			
	recalculate_performance_factors()
	
	# Initialize Physics State
	throttle = 1.0 # Start at full power
	current_speed = 60.0 # Start with good flight speed
	velocity = -global_transform.basis.z * current_speed
	
	if is_player:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		add_to_group("player")
	
	if team == GlobalEnums.Team.ALLY:
		add_to_group("ally")
	elif team == GlobalEnums.Team.ENEMY:
		add_to_group("enemy")
	
	# Physics Layer 설정 (충돌 최적화)
	_setup_physics_layers()

func _setup_components() -> void:
	# Setup input handler for player aircraft
	if is_player:
		var AircraftInputHandler = load("res://Scripts/Flight/Components/AircraftInputHandler.gd")
		input_handler = AircraftInputHandler.new()
		input_handler.mouse_sensitivity = mouse_sensitivity
		add_child(input_handler)
	
	# Setup weapon system
	var AircraftWeaponSystem = load("res://Scripts/Flight/Components/AircraftWeaponSystem.gd")
	weapon_system = AircraftWeaponSystem.new()
	weapon_system.fire_rate = fire_rate
	weapon_system.missile_cooldown = missile_cooldown
	weapon_system.missile_lock_range = missile_lock_range
	add_child(weapon_system)

func _setup_physics_layers() -> void:
	if is_player:
		collision_layer = 1  # Layer 1 (player)
		collision_mask = 4 | 8  # Layer 3 (enemy) + Layer 4 (ground)
	elif team == GlobalEnums.Team.ALLY:
		collision_layer = 2  # Layer 2 (ally)
		collision_mask = 4 | 8  # Layer 3 (enemy) + Layer 4 (ground)
	elif team == GlobalEnums.Team.ENEMY:
		collision_layer = 4  # Layer 3 (enemy)
		collision_mask = 1 | 2 | 8  # Layer 1 (player) + Layer 2 (ally) + Layer 4 (ground)


func calculate_physics(delta: float) -> void:
	# CPU-based physics calculation (New Vector-based Physics)
	
	# Wing destroyed - dramatic crash sequence
	if _wing_destroyed:
		_crash_timer += delta
		
		# Force throttle to 0 during crash
		throttle = 0.0
		
		# Apply crash rotation using FlightPhysics
		global_transform.basis = FlightPhysics.calculate_crash_rotation(
			global_transform.basis,
			_spin_factor,
			_crash_timer,
			pitch_speed,
			roll_speed,
			delta
		)
		
		# Simply let gravity and drag take over in the main vector logic below?
		# For dramatic effect, we might want explicit crash physics, but let's try to unify.
		# For now, keep the spin but use the vector physics for movement.
		# Just apply a chaotic force or simply let the bad aerodynamics (lift loss) do the work.
		
		# BUT existing crash logic was specific. Let's adapt it to vector physics.
		# Add gravity and drag manually here or fall through?
		# Let's fall through to the main physics block but with modified parameters (Zero Lift).
		pass # Logic continues below
		
	else:
		# Throttle adjustment
		if input_throttle_up:
			throttle = min(throttle + delta, 1.0)
		elif input_throttle_down:
			throttle = max(throttle - delta, 0.0)
			
		# Pitch control
		var pitch_input_adjusted = input_pitch * _c_h_tail_factor
		current_pitch = FlightPhysics.smooth_approach(current_pitch, pitch_input_adjusted, pitch_acceleration, delta)
		
		# Roll control
		var roll_input_adjusted = input_roll * _c_roll_authority
		var roll_bias = _c_wing_imbalance * 2.0
		current_roll = FlightPhysics.smooth_approach(current_roll, roll_input_adjusted + roll_bias, roll_acceleration, delta)
		
		# Apply Basis Rotation (Orientation)
		var current_basis = global_transform.basis
		current_basis = FlightPhysics.apply_pitch_rotation(current_basis, current_pitch, pitch_speed, delta)
		current_basis = FlightPhysics.apply_roll_rotation(current_basis, current_roll, roll_speed, delta)
		current_basis = current_basis.orthonormalized()
		global_transform.basis = current_basis
	
	# --- VECTOR PHYSICS ENGINE ---
	
	var forward = -global_transform.basis.z
	var up = global_transform.basis.y
	var right = global_transform.basis.x
	
	# Current State
	current_speed = velocity.length()
	var vel_dir = velocity.normalized() if current_speed > 0.01 else forward
	
	# 1. Gravity (Adjusted)
	var gravity_accel = Vector3(0, -9.8, 0)  # Standard gravity
	if _wing_destroyed:
		gravity_accel = Vector3(0, -19.6, 0) # Fall faster if destroyed
	
	# 2. Thrust (Forward)
	# Acceleration provides force. F = ma. Assuming mass=1.
	var thrust_accel = forward * throttle * acceleration * _c_engine_factor
	if _wing_destroyed: thrust_accel = Vector3.ZERO
	
	# 3. Drag (Opposite to Velocity)
	# Drag = Coeff * Speed^2
	var drag_magnitude = drag_factor * current_speed * current_speed
	if _wing_destroyed:
		drag_magnitude *= 5.0 # Massive drag from debris/spinning
		
	var drag_accel = -vel_dir * drag_magnitude
	
	# 4. Lift (Local Up, perpendicular to airflow)
	# Lift = Coeff * Speed^2 * AOA_Factor
	# Calculate Angle of Attack (AOA)
	var aoa = FlightPhysics.calculate_angle_of_attack(velocity, forward, right)
	var abs_aoa = abs(aoa)
	var stall_factor = FlightPhysics.calculate_stall_factor(abs_aoa)
	
	# Realistic Lift Calculation:
	# Lift is proportional to AOA (Linear aerodynamics approximation)
	# Curve: Linear up to 15 degrees, then drops off (Stall)
	var critical_aoa = 15.0
	# Wing Incidence: +4.5 degrees
	# Note: Model has 30° tilt, compensated by very low lift_factor
	var effective_aoa = aoa + 4.5
	var lift_coefficient = clamp(effective_aoa / critical_aoa, -1.0, 1.0)
	
	# Apply stall factor (reduces lift past critical angle)
	var final_lift_mult = lift_coefficient * stall_factor
	
	# Calculate Lift Force Vector
	# Target: Slight pitch (3-6 degrees) for level flight
	# At level (aoa=0): effective_aoa = 4.5, lift_coeff = 0.3
	# At 40m/s: Lift = 0.0082 × 1600 × 0.3 = 3.94 m/s² (40% of gravity)
	# At 40m/s + pitch 6°: effective_aoa ≈ 10.5°, lift_coeff = 0.7
	#   Lift = 0.0082 × 1600 × 0.7 = 9.18 m/s² (94% gravity - near level)
	# At 40m/s + pitch 8°: ≈ 11 m/s² (climb)
	
	var lift_magnitude = lift_factor * current_speed * current_speed * final_lift_mult * _c_lift_factor
	
	# Lift acts perpendicular to velocity (roughly Up vector)
	var lift_accel = up * lift_magnitude
	
	# Apply Forces
	# velocity += acceleration * delta
	velocity += (gravity_accel + thrust_accel + drag_accel + lift_accel) * delta
	
	# Update current_speed for logic references
	current_speed = velocity.length()
	
	# Emit physics info for HUD (only for player)
	if is_player:
		emit_signal("physics_updated", current_speed, global_position.y, velocity.y, aoa, stall_factor)
		
		# DEBUG: Display level flight status
		var pitch_angle = rad_to_deg(asin(clamp(-forward.y, -1.0, 1.0)))  # Pitch angle in degrees
		var climb_rate = velocity.y  # Vertical speed
		var lift_to_gravity_ratio = lift_magnitude / 9.8
		var is_level = abs(pitch_angle) < 5.0 and abs(climb_rate) < 2.0
		
		print("[FLIGHT] Speed: %.1f m/s | Pitch: %.1f° | AOA: %.1f° | Eff.AOA: %.1f° | Lift: %.2f m/s² (%.0f%% gravity) | Climb: %.1f m/s | Level: %s" % [
			current_speed,
			pitch_angle,
			aoa,
			effective_aoa,
			lift_magnitude,
			lift_to_gravity_ratio * 100.0,
			climb_rate,
			"YES" if is_level else "NO"
		])
	
	# Stall warning for player
	if is_player and stall_factor < 0.8:
		if randf() < 0.01:  # Very occasional warning
			pass # print("[WARNING] STALL! Angle of Attack: %.1f degrees" % aoa)

func _physics_process(delta: float) -> void:
	# CRITICAL: Prevent duplicate calls from inherited scenes
	# This can happen if scripts are attached to both parent and child scenes
	if not is_inside_tree():
		return
	
	# CRITICAL: Prevent physics death spiral
	# If delta is too large, skip this frame to catch up
	if delta > 0.1:  # More than 100ms per frame = severe lag
		push_warning("[Aircraft] Skipping physics frame due to severe lag (delta: %.3f)" % delta)
		return
	
	# Debug: Track call frequency
	_physics_call_count += 1
	_physics_call_timer += delta
	if _physics_call_timer >= 1.0:
		if is_player:
			var expected_fps = Engine.physics_ticks_per_second
			var actual_calls = _physics_call_count
			var ratio = float(actual_calls) / expected_fps
			# print("[Aircraft] Physics calls: ", actual_calls, " | Expected: ", expected_fps, " | Ratio: ", "%.2f" % ratio, "x")
			if ratio > 1.5:
				push_warning("[Aircraft] Physics process called ", ratio, "x more than expected!")
				push_warning("[Aircraft] Instance ID: ", get_instance_id(), " | Path: ", get_path())
		_physics_call_count = 0
		_physics_call_timer = 0.0
	
	if _performance_dirty:
		recalculate_performance_factors()
		_performance_dirty = false
	
	# Update input from InputHandler (if player)
	if is_player and is_instance_valid(input_handler):
		input_handler.process_input()
		input_pitch = input_handler.input_pitch
		input_roll = input_handler.input_roll
		input_fire = input_handler.input_fire
		input_missile = input_handler.input_missile
		input_throttle_up = input_handler.input_throttle_up
		input_throttle_down = input_handler.input_throttle_down
	
	# CPU-based physics calculation
	calculate_physics(delta)
	
	# Wing destroyed - force movement even in safe altitude
	var is_crashing = _wing_destroyed
	
	# Optimization: LOD for Physics (Physics LOD)
	# Only use expensive move_and_slide when collision is likely (Low altitude) or for Player.
	# This prevents the "Physics Death Spiral" where lag causes more physics steps, causing more lag.
	var safe_altitude = 50.0
	
	if is_player or is_crashing or global_position.y < safe_altitude:
		move_and_slide()
		
		if get_slide_collision_count() > 0:
			_handle_collision(delta)
	else:
		# Simple movement for AI in safe zone (High altitude)
		# This is much cheaper than move_and_slide()
		global_position += velocity * delta



func _handle_collision(_delta: float) -> void:
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		
		# Landing conditions: Low speed, flat angle
		var is_landing = FlightPhysics.check_landing_conditions(
			current_speed,
			transform.basis.y
		)
		
		if is_landing:
			# Safe landing, stop
			current_speed *= 0.95
		else:
			# Crash!
			die()

# Debug helper functions for InputHandler
func _debug_destroy_left_wing() -> void:
	parts_health["l_wing_in"] = 0.0
	parts_health["l_wing_out"] = 0.0
	break_part("l_wing_in")
	break_part("l_wing_out")

func _debug_destroy_right_wing() -> void:
	parts_health["r_wing_in"] = 0.0
	parts_health["r_wing_out"] = 0.0
	break_part("r_wing_in")
	break_part("r_wing_out")

func take_damage(amount: float, hit_pos_local: Vector3) -> void:
	if is_player:
		emit_signal("damage_taken", hit_pos_local)
	
	# Debug output
	var team_name = "PLAYER" if is_player else ("ALLY" if team == GlobalEnums.Team.ALLY else "ENEMY")
	print("[Aircraft] %s taking %.1f damage at local pos %s" % [team_name, amount, hit_pos_local])
	
	# Determine part using DamageSystem
	var part = DamageSystem.determine_hit_part(hit_pos_local)
	print("  → Hit part: %s (health: %.1f)" % [part, parts_health.get(part, 0.0)])
	
	if part in parts_health:
		parts_health[part] = max(0, parts_health[part] - amount)
		print("  → New health: %.1f" % parts_health[part])
		
		_performance_dirty = true
		
		if parts_health[part] <= 0:
			print("  → Part DESTROYED!")
			break_part(part)
		
		if DamageSystem.check_critical_damage(parts_health):
			print("  → CRITICAL DAMAGE - Aircraft destroyed!")
			die()

func break_part(part: String) -> void:
	var explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	get_parent().add_child(explosion)
	
	# Get node name using DamageSystem
	var node_name = DamageSystem.get_part_node_name(part)
	
	if node_name != "" and has_node(node_name):
		var node = get_node(node_name)
		if node.visible:
			node.hide()
			explosion.global_position = node.global_position
	else:
		explosion.global_position = global_position
	
	# Check wing destruction using DamageSystem
	if part in ["l_wing_out", "r_wing_out", "l_wing_in", "r_wing_in"]:
		var destruction = DamageSystem.check_wing_destruction(parts_health)
		
		if destruction["destroyed"]:
			_wing_destroyed = true
			_crash_timer = 0.0
			_spin_factor = destruction["spin_factor"]
			
			if is_player:
				print("[WARNING] Wing destroyed! Aircraft entering uncontrollable spin!")

func die() -> void:
	print("Aircraft destroyed!")
	
	# Stop processing immediately to prevent errors
	set_process(false)
	set_physics_process(false)
	
	if is_player:
		var cam = get_node_or_null("CameraRig")
		if cam:
			# Detach camera so it survives
			cam.reparent(get_parent())
			cam.enable_spectator_mode(self)
	
	var explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	get_parent().add_child(explosion)
	explosion.global_position = global_position
	explosion.scale = Vector3.ONE * 3.0 # Big explosion
	queue_free()

# Debug: Track physics_process calls
var _physics_call_count: int = 0
var _physics_call_timer: float = 0.0

func _process(delta: float) -> void:
	# CRITICAL: Validity check to prevent "previously freed instance" errors
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	
	if not is_instance_valid(weapon_system):
		return

	# Process weapons through weapon system
	if is_instance_valid(weapon_system):
		weapon_system.process_weapons(delta, input_fire, input_missile)
		
		# Update locked target reference
		if is_instance_valid(weapon_system):
			var potential_target = weapon_system.locked_target
			if is_instance_valid(potential_target):
				locked_target = potential_target
			else:
				locked_target = null
				
			last_fire_time = weapon_system.last_fire_time
			last_missile_time = weapon_system.last_missile_time
	
	# Player-only: target search
	if is_player and is_instance_valid(weapon_system):
		weapon_system.process_target_search(delta)
