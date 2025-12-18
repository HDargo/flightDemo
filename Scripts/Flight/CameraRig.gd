extends Node3D

class_name CameraRig

@export var target_path: NodePath
@export var smooth_speed: float = 5.0
@export var chase_offset: Vector3 = Vector3(0, 2, 6)
@export var cockpit_offset: Vector3 = Vector3(0, 0.8, -0.5)

# Speed FX
@export var base_fov: float = 75.0
@export var max_fov: float = 100.0
@export var shake_intensity: float = 0.05
@export var max_shake_speed: float = 80.0

@onready var camera: Camera3D = $Camera3D

var target: Node3D
var is_cockpit_view: bool = false
var is_spectator: bool = false
var spectator_target_index: int = 0

func _ready() -> void:
	if target_path:
		target = get_node(target_path)
	else:
		# Try to find parent if no target set
		target = get_parent()
	
	# Detach from parent rotation/position if needed, but if we use TopLevel, we are good.
	set_as_top_level(true)

func enable_spectator_mode(exclude_target: Node3D = null) -> void:
	is_spectator = true
	is_cockpit_view = false # Force chase view
	find_new_target(0, exclude_target)

func _unhandled_input(event: InputEvent) -> void:
	if not is_spectator: return
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			find_new_target(-1)
		elif event.keycode == KEY_E:
			find_new_target(1)

func find_new_target(direction: int, exclude_target: Node3D = null) -> void:
	var all_aircraft = []
	if FlightManager.instance:
		all_aircraft = FlightManager.instance.aircrafts
	else:
		all_aircraft = get_tree().get_nodes_in_group("ally") + get_tree().get_nodes_in_group("enemy")
		
	# Filter out dead or invalid ones
	var valid_aircraft = []
	for a in all_aircraft:
		if is_instance_valid(a) and not a.is_queued_for_deletion() and a != exclude_target:
			valid_aircraft.append(a)
	
	if valid_aircraft.is_empty():
		target = null
		return
		
	spectator_target_index += direction
	
	# Wrap around
	if spectator_target_index >= valid_aircraft.size():
		spectator_target_index = 0
	elif spectator_target_index < 0:
		spectator_target_index = valid_aircraft.size() - 1
		
	target = valid_aircraft[spectator_target_index]
	print("Spectating: ", target.name)

func toggle_view() -> void:
	is_cockpit_view = !is_cockpit_view
	
	# Notify HUD about view change
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_cockpit_view"):
		hud.set_cockpit_view(is_cockpit_view)

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		if is_spectator:
			find_new_target(1)
		return
	
	var target_pos = target.global_position
	var target_basis = target.global_transform.basis
	
	if is_cockpit_view:
		# Cockpit view: Snap directly to position/rotation (or very fast smooth)
		var desired_pos = target_pos + target_basis * cockpit_offset
		global_position = desired_pos
		global_transform.basis = target_basis
	else:
		# Chase view
		# Target position + offset rotated by target's basis
		var desired_pos = target_pos + target_basis * chase_offset
		
		# Smoothly move to desired position
		# Use frame-rate independent lerp: 1 - exp(-decay * dt)
		var t = 1.0 - exp(-smooth_speed * delta)
		global_position = global_position.lerp(desired_pos, t)
		
		# Look at target with ROLL synchronization
		# Look at a point far ahead of the target to anticipate movement
		var look_target = target_pos + target_basis * Vector3(0, 0, -20)
		var look_dir = global_position.direction_to(look_target)
		
		# Use target's UP vector to align camera roll with aircraft roll
		var target_up = target_basis.y
		
		# Robust Basis construction
		if look_dir.length_squared() > 0.001:
			# Prevent errors when look_dir is parallel to target_up
			if abs(look_dir.dot(target_up)) < 0.99:
				var target_basis_look = Basis.looking_at(look_dir, target_up)
				global_transform.basis = global_transform.basis.slerp(target_basis_look, t * 2.0).orthonormalized()
			else:
				# Fallback if weird angle: just rotate to target basis directly
				global_transform.basis = global_transform.basis.slerp(target_basis, t * 2.0).orthonormalized()

	# --- Speed FX (FOV & Shake) ---
	var speed = 0.0
	# Optimization: Avoid string lookup if possible, or cache the property check
	if target.get("current_speed") != null:
		speed = target.current_speed
	elif target is Node3D and "velocity" in target:
		speed = target.velocity.length()
	
	# Dynamic FOV
	var speed_ratio = clamp(speed / max_shake_speed, 0.0, 1.0)
	var target_fov = lerp(base_fov, max_fov, speed_ratio)
	if camera:
		camera.fov = lerp(camera.fov, target_fov, delta * 5.0)
		
		# Camera Shake
		if speed > 30.0:
			var shake_amount = (speed - 30.0) / (max_shake_speed - 30.0)
			shake_amount = clamp(shake_amount, 0.0, 1.0) * shake_intensity
			camera.h_offset = randf_range(-shake_amount, shake_amount)
			camera.v_offset = randf_range(-shake_amount, shake_amount)
		else:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
