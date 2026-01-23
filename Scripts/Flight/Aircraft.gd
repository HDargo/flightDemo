extends CharacterBody3D

class_name Aircraft

signal damage_taken(direction: Vector3)
signal physics_updated(speed: float, altitude: float, vertical_speed: float, aoa: float, stall_factor: float)

# Utility modules
const FlightPhysics = preload("res://Scripts/Flight/FlightPhysics.gd")
const DamageSystem = preload("res://Scripts/Flight/DamageSystem.gd")

# Aircraft Data
@export var aircraft_data: AircraftResource

# Components
var input_handler: Node = null
var weapon_system: Node = null
var visual: AircraftVisual = null
var _ai_controller: Node = null

# Settings
@export var max_speed: float = 50.0
@export var min_speed: float = 10.0
@export var acceleration: float = 90.0
@export var drag_factor: float = 0.006
@export var turn_speed: float = 2.0
@export var pitch_speed: float = 2.0
@export var roll_speed: float = 3.0
@export var pitch_acceleration: float = 5.0
@export var roll_acceleration: float = 5.0
@export var lift_factor: float = 0.00178
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
var current_yaw: float = 0.0 
var throttle: float = 0.0 
var input_pitch: float = 0.0
var input_roll: float = 0.0
var input_yaw: float = 0.0 
var input_fire: bool = false
var input_missile: bool = false
var input_throttle_up: bool = false
var input_throttle_down: bool = false
var input_flare: bool = false 

var last_fire_time: float = 0.0
var last_missile_time: float = 0.0
var last_flare_time: float = 0.0 
var flare_count: int = 30 
var flare_cooldown: float = 0.5
var missile_cooldown: float = 2.0
var locked_target: Node3D = null

# RWR State
var being_locked_count: int = 0
var incoming_missile_count: int = 0

# Optimization & Internal
var _performance_dirty: bool = false
var _last_physics_frame: int = -1
var _wing_destroyed: bool = false
var _spin_factor: float = 0.0
var _crash_timer: float = 0.0
var parts_health = {}
var max_part_healths = {}

func set_locked_by_enemy(active: bool) -> void:
	if active: being_locked_count += 1
	else: being_locked_count = max(0, being_locked_count - 1)

func set_missile_incoming(active: bool) -> void:
	if active: incoming_missile_count += 1
	else: incoming_missile_count = max(0, incoming_missile_count - 1)

func _initialize_from_resource() -> void:
	if not aircraft_data:
		parts_health = {"nose": 50.0, "fuselage": 150.0, "engine": 100.0, "l_wing_in": 80.0, "l_wing_out": 60.0, "r_wing_in": 80.0, "r_wing_out": 60.0, "v_tail": 60.0, "h_tail": 60.0}
		max_part_healths = parts_health.duplicate()
		return
	
	max_speed = aircraft_data.max_speed
	acceleration = aircraft_data.acceleration
	turn_speed = aircraft_data.turn_speed
	pitch_speed = aircraft_data.pitch_speed
	roll_speed = aircraft_data.roll_speed
	lift_factor = aircraft_data.lift_factor
	fire_rate = aircraft_data.fire_rate
	missile_lock_range = aircraft_data.missile_lock_range
	parts_health = aircraft_data.parts_health.duplicate()
	max_part_healths = parts_health.duplicate()
	
	if aircraft_data.visual_scene:
		for child in get_children():
			if child is MeshInstance3D: child.hide()
		var visual_instance = aircraft_data.visual_scene.instantiate()
		add_child(visual_instance)
		if visual_instance is AircraftVisual: visual = visual_instance
		if visual_instance.has_method("set_base_color"): visual_instance.set_base_color(aircraft_data.base_color)
		elif "base_color" in aircraft_data: _apply_color_to_node(visual_instance, aircraft_data.base_color)

func _apply_color_to_node(node: Node, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			child.set_surface_override_material(0, mat)
		_apply_color_to_node(child, color)

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

func _exit_tree() -> void:
	if weapon_system and "_target_search_task_id" in weapon_system:
		var task_id = weapon_system._target_search_task_id
		if task_id != -1: WorkerThreadPool.wait_for_task_completion(task_id)
	if FlightManager.instance:
		FlightManager.instance.unregister_aircraft(self)

func _ready() -> void:
	_initialize_from_resource()
	_setup_components()
	_ai_controller = get_node_or_null("AIController")
	
	if not FlightManager.instance:
		await get_tree().process_frame
		if FlightManager.instance: FlightManager.instance.register_aircraft(self)
			
	recalculate_performance_factors()
	throttle = 1.0 
	current_speed = max_speed
	velocity = - global_transform.basis.z * current_speed
	
	if is_player:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		add_to_group("player")
	
	if team == GlobalEnums.Team.ALLY: add_to_group("ally")
	elif team == GlobalEnums.Team.ENEMY: add_to_group("enemy")
	
	_setup_physics_layers()

func _setup_components() -> void:
	if is_player:
		var AircraftInputHandler = load("res://Scripts/Flight/Components/AircraftInputHandler.gd")
		input_handler = AircraftInputHandler.new()
		input_handler.mouse_sensitivity = mouse_sensitivity
		add_child(input_handler)
	var AircraftWeaponSystem = load("res://Scripts/Flight/Components/AircraftWeaponSystem.gd")
	weapon_system = AircraftWeaponSystem.new()
	# Legacy fallback if resource doesn't have loadout, pass props for legacy init
	weapon_system.fire_rate = fire_rate
	weapon_system.missile_cooldown = missile_cooldown
	weapon_system.missile_lock_range = missile_lock_range
	if aircraft_data and not aircraft_data.default_loadout.is_empty():
		weapon_system.default_weapons = aircraft_data.default_loadout
	add_child(weapon_system)

func _setup_physics_layers() -> void:
	if is_player:
		collision_layer = 1
		collision_mask = 4 | 8
	elif team == GlobalEnums.Team.ALLY:
		collision_layer = 2
		collision_mask = 4 | 8
	elif team == GlobalEnums.Team.ENEMY:
		collision_layer = 4
		collision_mask = 1 | 2 | 8

func calculate_physics(delta: float) -> void:
	var basis = global_transform.basis
	var forward = -basis.z
	var up = basis.y
	var right = basis.x
	
	if _wing_destroyed:
		_crash_timer += delta
		throttle = 0.0
		global_transform.basis = FlightPhysics.calculate_crash_rotation(basis, _spin_factor, _crash_timer, pitch_speed, roll_speed, delta)
	else:
		if input_throttle_up: throttle = min(throttle + delta, 1.0)
		elif input_throttle_down: throttle = max(throttle - delta, 0.0)
		current_pitch = FlightPhysics.smooth_approach(current_pitch, input_pitch * _c_h_tail_factor, pitch_acceleration, delta)
		current_roll = FlightPhysics.smooth_approach(current_roll, input_roll * _c_roll_authority + _c_wing_imbalance * 2.0, roll_acceleration, delta)
		basis = FlightPhysics.apply_pitch_rotation(basis, current_pitch, pitch_speed, delta)
		basis = FlightPhysics.apply_roll_rotation(basis, current_roll, roll_speed, delta)
		if Engine.get_physics_frames() % 10 == 0:
			basis = basis.orthonormalized()
		global_transform.basis = basis
	
	current_speed = velocity.length()
	var vel_dir = velocity / current_speed if current_speed > 0.1 else forward
	var total_accel = Vector3(0, -9.8, 0)
	if not _wing_destroyed:
		total_accel += forward * (throttle * acceleration * _c_engine_factor)
	else:
		total_accel.y = -19.6
	
	var speed_sq = velocity.length_squared()
	total_accel -= vel_dir * (drag_factor * speed_sq * (5.0 if _wing_destroyed else 1.0))
	
	if is_player or Engine.get_physics_frames() % 2 == 0:
		var aoa = FlightPhysics.calculate_angle_of_attack(velocity, forward, right)
		var stall_factor = FlightPhysics.calculate_stall_factor(abs(aoa))
		var lift_magnitude = lift_factor * speed_sq * clamp((aoa + 4.5) / 15.0, -1.0, 1.0) * stall_factor * _c_lift_factor
		total_accel += up * lift_magnitude
		if is_player: emit_signal("physics_updated", current_speed, global_position.y, velocity.y, aoa, stall_factor)
	
	velocity += total_accel * delta
	current_speed = velocity.length()

func _physics_process(delta: float) -> void:
	var current_frame = Engine.get_physics_frames()
	if _last_physics_frame == current_frame: return
	_last_physics_frame = current_frame
	
	if not is_inside_tree() or delta > 0.1: return
	
	if _performance_dirty:
		recalculate_performance_factors()
		_performance_dirty = false
	
	if is_player:
		if is_instance_valid(input_handler):
			input_handler.process_input()
			input_pitch = input_handler.input_pitch
			input_roll = input_handler.input_roll
			input_yaw = input_handler.input_yaw
			input_fire = input_handler.input_fire
			input_missile = input_handler.input_missile
			input_throttle_up = input_handler.input_throttle_up
			input_throttle_down = input_handler.input_throttle_down
			input_flare = input_handler.input_flare
	elif is_instance_valid(_ai_controller):
		_ai_controller.apply_inputs(delta)
	
	_process_flares(delta)
	calculate_physics(delta)
	
	if is_player or _wing_destroyed or global_position.y < 50.0:
		move_and_slide()
		if get_slide_collision_count() > 0: _handle_collision(delta)
	else:
		global_position += velocity * delta

func _handle_collision(_delta: float) -> void:
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		if FlightPhysics.check_landing_conditions(current_speed, transform.basis.y):
			current_speed *= 0.95
		else: die()

func take_damage(amount: float, hit_pos_local: Vector3) -> void:
	if is_player: emit_signal("damage_taken", hit_pos_local)
	var part = DamageSystem.determine_hit_part(hit_pos_local)
	if part in parts_health:
		parts_health[part] = max(0, parts_health[part] - amount)
		_update_part_visuals(part)
		_performance_dirty = true
		if parts_health[part] <= 0: break_part(part)
		if DamageSystem.check_critical_damage(parts_health): die()

func _update_part_visuals(part: String) -> void:
	if not visual: return
	var node = visual.get_part_node(part)
	if not node or (not node is MeshInstance3D and not node is CSGPrimitive3D): return
	var health_ratio = parts_health[part] / max_part_healths[part]
	var color_val = 0.2 + (health_ratio * 0.8)
	var damage_color = aircraft_data.base_color * color_val
	var mat = node.get_active_material(0)
	if mat:
		if not mat.resource_local_to_scene:
			mat = mat.duplicate()
			node.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D: mat.albedo_color = damage_color

func break_part(part: String) -> void:
	var explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	get_parent().add_child(explosion)
	if visual:
		var node = visual.get_part_node(part)
		if node:
			explosion.global_position = node.global_position
			visual.hide_part(part)
		else: explosion.global_position = global_position
	else:
		var node_name = DamageSystem.get_part_node_name(part)
		if node_name != "" and has_node(node_name):
			var node = get_node(node_name)
			node.hide()
			explosion.global_position = node.global_position
	
	if part in ["l_wing_out", "r_wing_out", "l_wing_in", "r_wing_in"]:
		var destruction = DamageSystem.check_wing_destruction(parts_health)
		if destruction["destroyed"]:
			_wing_destroyed = true
			_crash_timer = 0.0
			_spin_factor = destruction["spin_factor"]

func die() -> void:
	set_process(false)
	set_physics_process(false)
	if is_player:
		var cam = get_node_or_null("CameraRig")
		if cam:
			cam.reparent(get_parent())
			cam.enable_spectator_mode(self)
	var explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	get_parent().add_child(explosion)
	explosion.global_position = global_position
	explosion.scale = Vector3.ONE * 3.0
	queue_free()

func _process_flares(delta: float) -> void:
	if input_flare:
		var current_time = Time.get_ticks_msec() / 1000.0
		if flare_count > 0 and current_time - last_flare_time >= flare_cooldown:
			last_flare_time = current_time
			flare_count -= 1
			_spawn_flare()

func _spawn_flare() -> void:
	var flare = Node3D.new()
	flare.add_to_group("flares")
	get_parent().add_child(flare)
	var offset = Vector3(randf_range(-1, 1), -1, 1)
	flare.global_position = global_transform * offset
	var OmniLight = OmniLight3D.new()
	OmniLight.light_color = Color(1, 0.8, 0.2)
	OmniLight.omni_range = 10.0
	flare.add_child(OmniLight)
	get_tree().create_timer(3.0).timeout.connect(flare.queue_free)

func _process(delta: float) -> void:
	if not is_instance_valid(self) or is_queued_for_deletion(): return
	if visual and is_instance_valid(visual):
		var cam = get_viewport().get_camera_3d()
		if is_player or (cam and global_position.distance_squared_to(cam.global_position) < 16000000):
			visual.update_animation(input_pitch, input_roll, input_yaw, delta)
			visual.visible = true
		else: visual.visible = false
	if not is_instance_valid(weapon_system): return
	weapon_system.process_weapons(delta, input_fire, input_missile)
	if is_instance_valid(weapon_system):
		var potential_target = weapon_system.locked_target
		locked_target = potential_target if is_instance_valid(potential_target) else null
		last_fire_time = weapon_system.last_fire_time
		last_missile_time = weapon_system.last_missile_time
	if is_player and is_instance_valid(weapon_system): weapon_system.process_target_search(delta)
