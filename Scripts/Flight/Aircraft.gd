extends CharacterBody3D

class_name Aircraft

signal damage_taken(direction: Vector3)

# Settings
@export var max_speed: float = 50.0
@export var min_speed: float = 0.0
@export var acceleration: float = 20.0
@export var drag_factor: float = 0.01
@export var turn_speed: float = 2.0
@export var pitch_speed: float = 2.0
@export var roll_speed: float = 3.0
@export var pitch_acceleration: float = 5.0
@export var roll_acceleration: float = 5.0
@export var lift_factor: float = 0.5
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
	var engine_health_factor = parts_health["engine"] / max_part_healths["engine"]
	
	var l_wing_in_factor = parts_health["l_wing_in"] / max_part_healths["l_wing_in"]
	var l_wing_out_factor = parts_health["l_wing_out"] / max_part_healths["l_wing_out"]
	var r_wing_in_factor = parts_health["r_wing_in"] / max_part_healths["r_wing_in"]
	var r_wing_out_factor = parts_health["r_wing_out"] / max_part_healths["r_wing_out"]
	
	var l_lift = (l_wing_in_factor * 0.7) + (l_wing_out_factor * 0.3)
	var r_lift = (r_wing_in_factor * 0.7) + (r_wing_out_factor * 0.3)
	
	_c_engine_factor = engine_health_factor
	_c_lift_factor = (l_lift + r_lift) / 2.0
	_c_h_tail_factor = parts_health["h_tail"] / max_part_healths["h_tail"]
	_c_v_tail_factor = parts_health["v_tail"] / max_part_healths["v_tail"]
	
	var l_roll_authority = (l_wing_in_factor * 0.3) + (l_wing_out_factor * 0.7)
	var r_roll_authority = (r_wing_in_factor * 0.3) + (r_wing_out_factor * 0.7)
	_c_roll_authority = (l_roll_authority + r_roll_authority) / 2.0
	
	_c_wing_imbalance = r_lift - l_lift

# Thread-Safe Accumulators
var _pending_rotation: Vector3 = Vector3.ZERO # x=pitch, y=yaw, z=roll
var _cached_transform: Transform3D
var _calculation_velocity: Vector3

func prepare_for_threads() -> void:
	_cached_transform = global_transform
	_calculation_velocity = velocity

func prepare_for_threads_with_transform(tf: Transform3D) -> void:
	_cached_transform = tf
	_calculation_velocity = velocity

func _enter_tree() -> void:
	if FlightManager.instance:
		FlightManager.instance.register_aircraft(self)

var _target_search_task_id: int = -1
var _next_locked_target: Node3D = null

func _exit_tree() -> void:
	if _target_search_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_target_search_task_id)
	if FlightManager.instance:
		FlightManager.instance.unregister_aircraft(self)

func _ready() -> void:
	set_physics_process(false)
	
	if not FlightManager.instance:
		await get_tree().process_frame
		if FlightManager.instance:
			FlightManager.instance.register_aircraft(self)
			
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


func _physics_process(delta: float) -> void:
	if _performance_dirty:
		recalculate_performance_factors()
		_performance_dirty = false

# func calculate_forces(delta: float) -> void:
# 	# Logic moved to Compute Shader and _process
# 	pass



func _handle_collision(_delta: float) -> void:
	for i in range(get_slide_collision_count()):
		var _collision = get_slide_collision(i)
		# Assuming anything we hit is bad unless we are landing
		# Landing conditions: Low speed, flat angle
		
		var is_landing = false
		
		# Check up vector alignment with world up
		var up = transform.basis.y
		var dot = up.dot(Vector3.UP) # 1.0 is upright
		
		if current_speed < 20.0 and dot > 0.9:
			is_landing = true
		
		if is_landing:
			# Safe landing, stop
			# current_speed = move_toward(current_speed, 0.0, 10.0 * delta) # Delta not available here easily, assume small step or pass it
			# Let's just dampen speed
			current_speed *= 0.95
			# print("Landing...")
		else:
			# Crash!
			# print("CRASH!")
			die()

func process_player_input() -> void:
	# Keyboard overrides or adds to mouse
	var key_pitch = Input.get_axis("ui_up", "ui_down") 
	var key_roll = Input.get_axis("ui_left", "ui_right")
	
	# Invert keys for Arcade-style control (Up=Up, Right=Right)
	# Removed mouse input for steering to unify controls to keyboard
	input_pitch = -key_pitch 
	input_roll = -key_roll
	
	# Mouse Input (Accumulated from _unhandled_input)
	if mouse_input.length_squared() > 0:
		# Add mouse input to keyboard input
		# Sensitivity is already applied in _unhandled_input
		input_pitch += mouse_input.y
		input_roll += mouse_input.x
		
		# Reset accumulator for next frame
		mouse_input = Vector2.ZERO
	
	# Weapons: Space (Guns), F (Missile)
	input_fire = Input.is_key_pressed(KEY_SPACE)
	input_missile = Input.is_key_pressed(KEY_F)
	
	# Throttle: Shift (Up), Ctrl (Down)
	# Note: You might need to map these in Project Settings -> Input Map if not using default UI actions.
	# For now, let's use physical keys if possible or standard UI actions if they map well.
	# ui_accept is usually Space/Enter. ui_cancel is Esc.
	# Let's use specific keys for better sim feel.
	input_throttle_up = Input.is_key_pressed(KEY_SHIFT)
	input_throttle_down = Input.is_key_pressed(KEY_CTRL)
	
	# Toggle Mouse Capture - REMOVED (Handled by PauseMenu)
	# if Input.is_action_just_pressed("ui_cancel"): ...
	pass

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

func take_damage(amount: float, hit_pos_local: Vector3) -> void:
	if is_player:
		emit_signal("damage_taken", hit_pos_local)
		
	# Determine part based on local position
	var part = "fuselage"
	
	# Z: Forward is -Z. Back is +Z.
	# X: Right is +X. Left is -X.
	
	if hit_pos_local.z < -2.0:
		part = "nose"
	elif hit_pos_local.z < -1.0:
		part = "engine"
	elif hit_pos_local.z > 2.0:
		if abs(hit_pos_local.x) < 0.5:
			part = "v_tail"
		else:
			part = "h_tail"
	elif abs(hit_pos_local.x) > 0.5:
		if hit_pos_local.x < -2.0:
			part = "l_wing_out"
		elif hit_pos_local.x < -0.5:
			part = "l_wing_in"
		elif hit_pos_local.x > 2.0:
			part = "r_wing_out"
		elif hit_pos_local.x > 0.5:
			part = "r_wing_in"
	
	if part in parts_health:
		parts_health[part] = max(0, parts_health[part] - amount)
		# print("Hit %s! Health: %.1f" % [part, parts_health[part]])
		
		_performance_dirty = true
		
		if parts_health[part] <= 0:
			break_part(part)
		
		if parts_health["fuselage"] <= 0:
			die()

func break_part(part: String) -> void:
	var explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	get_parent().add_child(explosion)
	
	# Map part names to node names
	var node_name = ""
	match part:
		"nose": node_name = "Nose"
		"engine": node_name = "Engine"
		"l_wing_in": node_name = "LeftWingIn"
		"l_wing_out": node_name = "LeftWingOut"
		"r_wing_in": node_name = "RightWingIn"
		"r_wing_out": node_name = "RightWingOut"
		"v_tail": node_name = "VerticalTail"
		"h_tail": node_name = "HorizontalTail"
	
	if node_name != "" and has_node(node_name):
		var node = get_node(node_name)
		if node.visible:
			node.hide()
			explosion.global_position = node.global_position
	else:
		explosion.global_position = global_position

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
		# print("No target locked!")
		return
	
	last_missile_time = current_time
	
	if FlightManager.instance:
		var launch_tf = global_transform * Transform3D(Basis(), Vector3(0, -1, 0)) # Drop from belly
		FlightManager.instance.spawn_missile(launch_tf, locked_target, current_speed + 50.0)
		print("Missile fired at ", locked_target.name)
	else:
		# Fallback
		var missile = missile_scene.instantiate()
		missile.speed = current_speed + 50.0 # Launch with boost
		get_parent().add_child(missile)
		missile.global_transform = global_transform * Transform3D(Basis(), Vector3(0, -1, 0)) # Drop from belly
		missile.target = locked_target
		print("Missile fired at ", locked_target.name)

var _target_search_timer: float = 0.0
var _target_search_interval: float = 0.2 # 5 times per second

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
