extends CharacterBody3D

class_name Aircraft

signal damage_taken(direction: Vector3)
signal physics_updated(speed: float, altitude: float, vertical_speed: float, aoa: float, stall_factor: float)

# Utility modules
const FlightPhysics = preload("res://Scripts/Flight/FlightPhysics.gd")
const DamageSystem = preload("res://Scripts/Flight/DamageSystem.gd")

# Settings
@export var max_speed: float = 50.0
@export var min_speed: float = 10.0  # Minimum flight speed to maintain lift
@export var acceleration: float = 20.0
@export var drag_factor: float = 0.01
@export var turn_speed: float = 2.0
@export var pitch_speed: float = 2.0
@export var roll_speed: float = 3.0
@export var pitch_acceleration: float = 5.0
@export var roll_acceleration: float = 5.0
@export var lift_factor: float = 0.05  # Reduced for speed^2 formula
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

var mouse_input: Vector2 = Vector2.ZERO
var last_fire_time: float = 0.0
var last_missile_time: float = 0.0
var missile_cooldown: float = 2.0
var locked_target: Node3D = null
var _performance_dirty: bool = false
var _missile_wing_toggle: bool = false  # Toggle between left and right wing

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

var _target_search_task_id: int = -1
var _next_locked_target: Node3D = null

func _exit_tree() -> void:
	if _target_search_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_target_search_task_id)
	if FlightManager.instance:
		FlightManager.instance.unregister_aircraft(self)

func _ready() -> void:
	# Physics process is enabled by default for CharacterBody3D
	
	# Only register if not already registered in _enter_tree
	if not FlightManager.instance:
		await get_tree().process_frame
		if FlightManager.instance:
			FlightManager.instance.register_aircraft(self)
			if is_player:
				print("[Aircraft] Player aircraft registered (delayed): ", get_instance_id())
			
	recalculate_performance_factors()
	# current_speed = min_speed
	current_speed = 10.0
	if is_player:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		add_to_group("player")
	
	if team == GlobalEnums.Team.ALLY:
		add_to_group("ally")
	elif team == GlobalEnums.Team.ENEMY:
		add_to_group("enemy")
	
	# Physics Layer 설정 (충돌 최적화)
	_setup_physics_layers()

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
	# CPU-based physics calculation (replaces GPU compute shader)
	
	# Wing destroyed - dramatic crash sequence
	if _wing_destroyed:
		_crash_timer += delta
		
		# Force throttle to 0 during crash
		throttle = 0.0
		current_speed = max(min_speed * 0.3, current_speed - acceleration * delta * 3.0)
		
		# Apply crash rotation using FlightPhysics
		global_transform.basis = FlightPhysics.calculate_crash_rotation(
			global_transform.basis,
			_spin_factor,
			_crash_timer,
			pitch_speed,
			roll_speed,
			delta
		)
		
		# Calculate horizontal velocity using FlightPhysics
		var forward = -global_transform.basis.z
		var horizontal_velocity = FlightPhysics.calculate_crash_horizontal_velocity(forward, current_speed)
		
		# Keep existing vertical velocity and add gravity
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z
		velocity.y -= 19.6 * delta  # Double gravity - accumulates each frame
		
		# Auto-destroy if falling too long or hit ground level
		if _crash_timer > 8.0 or global_position.y < 5.0:
			die()
		
		# Don't execute normal flight physics when crashing
	else:
		# Normal flight physics
		# Throttle adjustment - only change if input is given
		if input_throttle_up:
			throttle = min(throttle + delta, 1.0)
		elif input_throttle_down:
			throttle = max(throttle - delta, 0.0)
		# If no input, maintain current throttle
		
		# Speed control using FlightPhysics
		var target_speed = FlightPhysics.calculate_target_speed(throttle, min_speed, max_speed, _c_engine_factor)
		current_speed = FlightPhysics.smooth_approach(current_speed, target_speed, acceleration * _c_engine_factor, delta)
		
		# Drag
		var drag = FlightPhysics.calculate_drag(current_speed, drag_factor, delta)
		current_speed = max(min_speed, current_speed - drag)
		
		# Pitch control with damage
		var pitch_input_adjusted = input_pitch * _c_h_tail_factor
		current_pitch = FlightPhysics.smooth_approach(current_pitch, pitch_input_adjusted, pitch_acceleration, delta)
		
		# Roll control with damage
		var roll_input_adjusted = input_roll * _c_roll_authority
		var roll_bias = _c_wing_imbalance * 2.0
		current_roll = FlightPhysics.smooth_approach(current_roll, roll_input_adjusted + roll_bias, roll_acceleration, delta)
		
		# Apply rotation using FlightPhysics
		var current_basis = global_transform.basis
		current_basis = FlightPhysics.apply_pitch_rotation(current_basis, current_pitch, pitch_speed, delta)
		current_basis = FlightPhysics.apply_roll_rotation(current_basis, current_roll, roll_speed, delta)
		current_basis = current_basis.orthonormalized()
		global_transform.basis = current_basis
		
		# Lift force
		var forward = -global_transform.basis.z
		var up = global_transform.basis.y
		
		# Calculate angle of attack (받음각)
		var aoa = FlightPhysics.calculate_angle_of_attack(velocity, forward)
		var stall_factor = FlightPhysics.calculate_stall_factor(aoa)
		
		# Lift calculation with stall factor
		var lift = FlightPhysics.calculate_lift(current_speed, lift_factor * stall_factor, _c_lift_factor, up)
		
		# DEBUG: Print physics values
		if is_player and int(Time.get_ticks_msec() / 1000.0) != _last_debug_second:
			_last_debug_second = int(Time.get_ticks_msec() / 1000.0)
			print("=== PHYSICS DEBUG ===")
			print("Speed: %.1f | Throttle: %.1f%%" % [current_speed, throttle * 100])
			print("Lift: %s (%.2f)" % [lift, lift.length()])
			print("Up: %s (y=%.2f)" % [up, up.y])
			print("Forward: %s" % forward)
			print("AOA: %.1f° | Stall: %.2f" % [aoa, stall_factor])
		
		# Update velocity (ORIGINAL WORKING METHOD)
		# Velocity = forward motion + lift force
		velocity = forward * current_speed + lift * delta
		
		# Apply gravity
		velocity.y -= 9.8 * delta
		
		# DEBUG
		if is_player and _last_debug_second == int(Time.get_ticks_msec() / 1000.0):
			print("Velocity: %s (%.2f)" % [velocity, velocity.length()])
			print("Velocity.y: %.2f" % velocity.y)
		
		# Emit physics info for HUD (only for player)
		if is_player:
			emit_signal("physics_updated", current_speed, global_position.y, velocity.y, aoa, stall_factor)
		
		# Stall warning for player
		if is_player and stall_factor < 0.8:
			if randf() < 0.1:  # Occasional warning
				print("[WARNING] STALL! Angle of Attack: %.1f degrees" % aoa)

func _physics_process(delta: float) -> void:
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
			print("[Aircraft] Physics calls: ", actual_calls, " | Expected: ", expected_fps, " | Ratio: ", "%.2f" % ratio, "x")
			if ratio > 1.5:
				push_warning("[Aircraft] Physics process called ", ratio, "x more than expected!")
		_physics_call_count = 0
		_physics_call_timer = 0.0
	
	if _performance_dirty:
		recalculate_performance_factors()
		_performance_dirty = false
	
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
		
		# DEBUG: Ground collision check
		if is_player and global_position.y < 10.0:
			print("[Aircraft] Low altitude: %.1f | Collisions: %d" % [global_position.y, get_slide_collision_count()])
		
		if get_slide_collision_count() > 0:
			_handle_collision(delta)
	else:
		# Simple movement for AI in safe zone (High altitude)
		# This is much cheaper than move_and_slide()
		global_position += velocity * delta



func _handle_collision(_delta: float) -> void:
	if is_player:
		print("[Aircraft] COLLISION DETECTED! Count: %d" % get_slide_collision_count())
	
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		
		if is_player:
			print("  Collision %d: %s at %s" % [i, collision.get_collider(), collision.get_position()])
		
		# Landing conditions: Low speed, flat angle
		var is_landing = FlightPhysics.check_landing_conditions(
			current_speed,
			transform.basis.y
		)
		
		if is_player:
			print("  Speed: %.1f | Is Landing: %s" % [current_speed, is_landing])
		
		if is_landing:
			# Safe landing, stop
			current_speed *= 0.95
			if is_player:
				print("  → LANDING (speed reduced)")
		else:
			# Crash!
			if is_player:
				print("  → CRASH! Destroying aircraft...")
			die()

func process_player_input() -> void:
	# Get input from new input actions (supports keyboard, joystick, mouse)
	var pitch_input = Input.get_axis("flight_pitch_up", "flight_pitch_down")
	var roll_input = Input.get_axis("flight_roll_left", "flight_roll_right")
	
	# Apply pitch and roll (inverted for correct feel)
	input_pitch = -pitch_input
	input_roll = -roll_input
	
	# Mouse Input (Accumulated from _unhandled_input)
	if mouse_input.length_squared() > 0:
		# Add mouse input to keyboard/joystick input
		# Sensitivity is already applied in _unhandled_input
		input_pitch += mouse_input.y
		input_roll += mouse_input.x
		
		# Reset accumulator for next frame
		mouse_input = Vector2.ZERO
	
	# Weapons
	input_fire = Input.is_action_pressed("flight_fire_gun")
	input_missile = Input.is_action_pressed("flight_fire_missile")
	
	# Throttle
	input_throttle_up = Input.is_action_pressed("flight_throttle_up")
	input_throttle_down = Input.is_action_pressed("flight_throttle_down")

func _unhandled_input(event: InputEvent) -> void:
	if not is_player: return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Accumulate mouse delta
		# Pitch (Y): Up is negative in screen, but we want Up to pitch up (positive or negative depending on convention)
		# Usually Pull Back (Mouse Down) -> Pitch Up.
		# Mouse Down is +Y.
		# So +Y -> Pitch Up.
		
		# Roll (X): Mouse Right -> Roll Right.
		# Mouse Right is +X.
		# So +X -> Roll Right.
		
		mouse_input.y += event.relative.y * mouse_sensitivity
		mouse_input.x += event.relative.x * mouse_sensitivity

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		var cam = get_node_or_null("CameraRig")
		if cam:
			cam.toggle_view()
	
	# Debug: Test wing damage
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			# Destroy left wing
			print("[DEBUG] Destroying left wing...")
			parts_health["l_wing_in"] = 0.0
			parts_health["l_wing_out"] = 0.0
			break_part("l_wing_in")
			break_part("l_wing_out")
		elif event.keycode == KEY_Y:
			# Destroy right wing
			print("[DEBUG] Destroying right wing...")
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

func _deferred_shoot() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_fire_time < fire_rate:
		return
	
	last_fire_time = current_time
	
	# Spawn projectiles (Twin guns)
	var offsets = [Vector3(1.5, 0, -1), Vector3(-1.5, 0, -1)] # Wing mounted
	
	if FlightManager.instance:
		for offset in offsets:
			var tf = global_transform * Transform3D(Basis(), offset)
			FlightManager.instance.spawn_projectile(tf)

func _deferred_fire_missile() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_missile_time < missile_cooldown:
		return
	
	# Use locked target
	if not is_instance_valid(locked_target):
		return
	
	last_missile_time = current_time
	
	# Alternate wing hardpoints
	_missile_wing_toggle = !_missile_wing_toggle
	var wing_offset = Vector3(3.5 if _missile_wing_toggle else -3.5, -1.5, -5.0)
	
	# Calculate spawn transform
	var launch_transform = global_transform * Transform3D(Basis(), wing_offset)
	
	# Spawn via manager
	if FlightManager.instance:
		FlightManager.instance.spawn_missile(launch_transform, locked_target, self)
		print("Missile fired at ", locked_target.name)

var _target_search_timer: float = 0.0
var _target_search_interval: float = 0.2 # 5 times per second

# Debug: Track physics_process calls
var _physics_call_count: int = 0
var _physics_call_timer: float = 0.0

func _process(delta: float) -> void:
	# Logic from calculate_forces
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if input_fire and (current_time - last_fire_time >= fire_rate):
		call_deferred("_deferred_shoot")
	
	if input_missile and (current_time - last_missile_time >= missile_cooldown):
		call_deferred("_deferred_fire_missile")
	
	if input_throttle_up:
		throttle = min(throttle + delta, 1.0)
	elif input_throttle_down:
		throttle = max(throttle - delta, 0.0)

	if is_player:
		# 1. Process Input on Main Thread (Safe)
		process_player_input()
		
		# 2. Check Async Search Result
		if _target_search_task_id != -1:
			if WorkerThreadPool.is_task_completed(_target_search_task_id):
				WorkerThreadPool.wait_for_task_completion(_target_search_task_id)
				_target_search_task_id = -1
				locked_target = _next_locked_target
		
		# 3. Throttle Target Search
		_target_search_timer -= delta
		if _target_search_timer <= 0 and _target_search_task_id == -1:
			_target_search_timer = _target_search_interval
			_start_target_search()

func _start_target_search() -> void:
	if not FlightManager.instance: return
	
	# Snapshot data for thread
	var enemies = FlightManager.instance.get_enemies_of(team).duplicate()
	var params = {
		"targets": enemies,
		"my_pos": global_position,
		"my_forward": -global_transform.basis.z,
		"range_sq": missile_lock_range * missile_lock_range
	}
	
	_target_search_task_id = WorkerThreadPool.add_task(
		_thread_find_target.bind(params),
		true,
		"Target Search"
	)

func _thread_find_target(params: Dictionary) -> void:
	var best_target = null
	var best_angle = 0.5
	var my_pos = params.my_pos
	var my_forward = params.my_forward
	var range_sq = params.range_sq
	
	for entry in params.targets:
		if not is_instance_valid(entry.ref): continue
		
		var to_target = entry.pos - my_pos
		var dist_sq = to_target.length_squared()
		if dist_sq > range_sq: continue
		
		# Optimize: Avoid full normalization (3 divisions)
		# angle = dot(forward, to_target.normalized())
		#       = dot(forward, to_target / dist)
		#       = dot(forward, to_target) / dist
		
		var dist = sqrt(dist_sq)
		if dist < 0.001: continue
		
		var angle = my_forward.dot(to_target) / dist
		
		if angle > best_angle:
			best_angle = angle
			best_target = entry.ref
			
	_next_locked_target = best_target
