extends Node

class_name MassAircraftSystem

## Large-scale aircraft simulation using PackedArrays and GPU Compute Shaders
## Handles 1000+ aircraft efficiently

static var instance: MassAircraftSystem

# Packed Arrays for CPU-side data (Thread-safe)
var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var rotations: PackedVector3Array = PackedVector3Array()  # Euler angles
var speeds: PackedFloat32Array = PackedFloat32Array()
var throttles: PackedFloat32Array = PackedFloat32Array()
var healths: PackedFloat32Array = PackedFloat32Array()
var teams: PackedInt32Array = PackedInt32Array()
var states: PackedInt32Array = PackedInt32Array()  # Active/Dead flags

# Performance Parameters (per aircraft)
var engine_factors: PackedFloat32Array = PackedFloat32Array()
var lift_factors: PackedFloat32Array = PackedFloat32Array()
var roll_authorities: PackedFloat32Array = PackedFloat32Array()

# AI Input Arrays
var input_pitches: PackedFloat32Array = PackedFloat32Array()
var input_rolls: PackedFloat32Array = PackedFloat32Array()
var input_yaws: PackedFloat32Array = PackedFloat32Array()

# Rendering (LOD support)
var _multimesh_ally_high: MultiMeshInstance3D
var _multimesh_ally_med: MultiMeshInstance3D
var _multimesh_ally_low: MultiMeshInstance3D
var _multimesh_enemy_high: MultiMeshInstance3D
var _multimesh_enemy_med: MultiMeshInstance3D
var _multimesh_enemy_low: MultiMeshInstance3D

# LOD distance thresholds (squared)
const LOD_HIGH_DIST_SQ: float = 250000.0    # 500m
const LOD_MEDIUM_DIST_SQ: float = 4000000.0 # 2000m

# GPU Compute Shader
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _uniform_set: RID
var _buffer: RID
var _use_compute_shader: bool = false
var _gpu_task_pending: bool = false

# Constants
const MAX_AIRCRAFT: int = 2000
const STRUCT_SIZE: int = 176  # bytes per aircraft in GPU buffer
# Layout: mat4(64) + vec4(16) + vec4(16) + vec4(16) + vec4(16) + vec4(16) + vec4(16) + vec4(16) = 176

# Aircraft parameters (shared by all)
@export var max_speed: float = 50.0
@export var min_speed: float = 10.0
@export var acceleration: float = 20.0
@export var drag_factor: float = 0.01
@export var lift_factor: float = 0.5
@export var pitch_speed: float = 2.0
@export var roll_speed: float = 3.0
@export var pitch_acceleration: float = 5.0
@export var roll_acceleration: float = 5.0

# Stats
var active_count: int = 0
var ally_count: int = 0
var enemy_count: int = 0

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	_cleanup_gpu_resources()
	if instance == self:
		instance = null

func _ready() -> void:
	_initialize_arrays()
	_setup_multimesh()
	_initialize_compute_shader()

func _initialize_arrays() -> void:
	positions.resize(MAX_AIRCRAFT)
	velocities.resize(MAX_AIRCRAFT)
	rotations.resize(MAX_AIRCRAFT)
	speeds.resize(MAX_AIRCRAFT)
	throttles.resize(MAX_AIRCRAFT)
	healths.resize(MAX_AIRCRAFT)
	teams.resize(MAX_AIRCRAFT)
	states.resize(MAX_AIRCRAFT)
	
	engine_factors.resize(MAX_AIRCRAFT)
	lift_factors.resize(MAX_AIRCRAFT)
	roll_authorities.resize(MAX_AIRCRAFT)
	
	input_pitches.resize(MAX_AIRCRAFT)
	input_rolls.resize(MAX_AIRCRAFT)
	input_yaws.resize(MAX_AIRCRAFT)
	
	# Initialize all as inactive
	for i in range(MAX_AIRCRAFT):
		states[i] = 0  # 0 = inactive, 1 = active

func _setup_multimesh() -> void:
	# Ally LODs
	_multimesh_ally_high = _create_lod_multimesh(_create_high_lod_mesh(Color(0.2, 0.5, 1.0)))
	_multimesh_ally_med = _create_lod_multimesh(_create_med_lod_mesh(Color(0.2, 0.5, 1.0)))
	_multimesh_ally_low = _create_lod_multimesh(_create_low_lod_mesh(Color(0.2, 0.5, 1.0)))
	
	add_child(_multimesh_ally_high)
	add_child(_multimesh_ally_med)
	add_child(_multimesh_ally_low)
	
	# Enemy LODs
	_multimesh_enemy_high = _create_lod_multimesh(_create_high_lod_mesh(Color(1.0, 0.3, 0.2)))
	_multimesh_enemy_med = _create_lod_multimesh(_create_med_lod_mesh(Color(1.0, 0.3, 0.2)))
	_multimesh_enemy_low = _create_lod_multimesh(_create_low_lod_mesh(Color(1.0, 0.3, 0.2)))
	
	add_child(_multimesh_enemy_high)
	add_child(_multimesh_enemy_med)
	add_child(_multimesh_enemy_low)

func _create_lod_multimesh(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = MAX_AIRCRAFT
	mm.visible_instance_count = 0
	mm.mesh = mesh
	mmi.multimesh = mm
	return mmi

func _create_high_lod_mesh(color: Color) -> Mesh:
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.7
	mesh.material = mat
	
	return mesh

func _create_med_lod_mesh(color: Color) -> Mesh:
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 2.0
	mesh.radial_segments = 4
	mesh.rings = 2
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	
	return mesh

func _create_low_lod_mesh(color: Color) -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.4, 0.4, 1.5)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	
	return mesh

func _create_simple_aircraft_mesh(color: Color) -> Mesh:
	# Simple aircraft shape: Capsule body + box wings
	var arr_mesh = ArrayMesh.new()
	
	# Body (Capsule)
	var body = CapsuleMesh.new()
	body.radius = 0.3
	body.height = 2.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	body.material = mat
	
	return body

func _initialize_compute_shader() -> void:
	# Try to create RenderingDevice (only works with Vulkan backend)
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_warning("[MassAircraftSystem] Compute shaders not available (requires Vulkan). Using CPU fallback.")
		_use_compute_shader = false
		return
	
	# Load compute shader
	var shader_file = load("res://Assets/Shaders/Compute/aerodynamics.glsl")
	if not shader_file:
		push_warning("[MassAircraftSystem] Compute shader not found. Using CPU fallback.")
		_use_compute_shader = false
		return
	
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	
	# Create GPU buffer
	var buffer_size = MAX_AIRCRAFT * STRUCT_SIZE
	var buffer_data = PackedByteArray()
	buffer_data.resize(buffer_size)
	
	_buffer = _rd.storage_buffer_create(buffer_size, buffer_data)
	
	# Create uniform
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(_buffer)
	
	_uniform_set = _rd.uniform_set_create([uniform], _shader, 0)
	
	_use_compute_shader = true
	print("[MassAircraftSystem] Compute shader initialized successfully")

func _cleanup_gpu_resources() -> void:
	if not _rd:
		return
	
	if _gpu_task_pending:
		_rd.sync()
		_gpu_task_pending = false
	
	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
	if _buffer.is_valid():
		_rd.free_rid(_buffer)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	
	_rd = null

func spawn_aircraft(pos: Vector3, team: int, initial_rotation: Vector3 = Vector3.ZERO) -> int:
	# Find inactive slot
	for i in range(MAX_AIRCRAFT):
		if states[i] == 0:
			positions[i] = pos
			velocities[i] = Vector3.ZERO
			rotations[i] = initial_rotation
			speeds[i] = min_speed
			throttles[i] = 0.5
			healths[i] = 100.0
			teams[i] = team
			states[i] = 1  # Active
			
			# Default performance
			engine_factors[i] = 1.0
			lift_factors[i] = 1.0
			roll_authorities[i] = 1.0
			
			# Default AI inputs
			input_pitches[i] = 0.0
			input_rolls[i] = 0.0
			input_yaws[i] = 0.0
			
			active_count += 1
			if team == GlobalEnums.Team.ALLY:
				ally_count += 1
			elif team == GlobalEnums.Team.ENEMY:
				enemy_count += 1
			
			return i
	
	push_warning("[MassAircraftSystem] Max aircraft limit reached!")
	return -1

func destroy_aircraft(index: int) -> void:
	if index < 0 or index >= MAX_AIRCRAFT:
		return
	
	if states[index] == 1:
		var team = teams[index]
		states[index] = 0  # Inactive
		active_count -= 1
		
		if team == GlobalEnums.Team.ALLY:
			ally_count -= 1
		elif team == GlobalEnums.Team.ENEMY:
			enemy_count -= 1

func get_aircraft_position(index: int) -> Vector3:
	if index < 0 or index >= MAX_AIRCRAFT or states[index] == 0:
		return Vector3.ZERO
	return positions[index]

func get_aircraft_team(index: int) -> int:
	if index < 0 or index >= MAX_AIRCRAFT or states[index] == 0:
		return GlobalEnums.Team.NEUTRAL
	return teams[index]

func _physics_process(delta: float) -> void:
	if active_count == 0:
		# Hide all LOD multimeshes
		_multimesh_ally_high.multimesh.visible_instance_count = 0
		_multimesh_ally_med.multimesh.visible_instance_count = 0
		_multimesh_ally_low.multimesh.visible_instance_count = 0
		_multimesh_enemy_high.multimesh.visible_instance_count = 0
		_multimesh_enemy_med.multimesh.visible_instance_count = 0
		_multimesh_enemy_low.multimesh.visible_instance_count = 0
		return
	
	if _use_compute_shader:
		_update_physics_gpu(delta)
	else:
		_update_physics_cpu(delta)
	
	_update_rendering()

func _update_physics_gpu(delta: float) -> void:
	# 1. Sync and read results from PREVIOUS frame (if any)
	if _gpu_task_pending:
		_rd.sync()
		var result_bytes = _rd.buffer_get_data(_buffer)
		_unpack_aircraft_data(result_bytes)
		_gpu_task_pending = false
	
	# 2. Upload data for CURRENT frame
	# Note: We are using the state updated from the previous frame's result
	var buffer_data = _pack_aircraft_data(delta)
	_rd.buffer_update(_buffer, 0, buffer_data.size(), buffer_data)
	
	# 3. Dispatch compute shader for CURRENT frame
	var compute_list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	
	# Dispatch (64 threads per workgroup)
	var workgroups = ceili(float(active_count) / 64.0)
	_rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
	_rd.compute_list_end()
	
	# 4. Submit but DO NOT sync immediately
	_rd.submit()
	_gpu_task_pending = true


func _pack_aircraft_data(delta: float) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(MAX_AIRCRAFT * STRUCT_SIZE)
	
	for i in range(MAX_AIRCRAFT):
		if states[i] == 0:
			continue
		
		var offset = i * STRUCT_SIZE
		var pos = positions[i]
		var vel = velocities[i]
		var rot = rotations[i]
		
		# Transform (mat4) - 64 bytes
		var basis = Basis.from_euler(rot)
		
		# Pack mat4 column-major (as GLSL expects)
		# Column 0 (basis.x)
		data.encode_float(offset, basis.x.x)
		data.encode_float(offset + 4, basis.x.y)
		data.encode_float(offset + 8, basis.x.z)
		data.encode_float(offset + 12, 0.0)
		
		# Column 1 (basis.y)
		data.encode_float(offset + 16, basis.y.x)
		data.encode_float(offset + 20, basis.y.y)
		data.encode_float(offset + 24, basis.y.z)
		data.encode_float(offset + 28, 0.0)
		
		# Column 2 (basis.z)
		data.encode_float(offset + 32, basis.z.x)
		data.encode_float(offset + 36, basis.z.y)
		data.encode_float(offset + 40, basis.z.z)
		data.encode_float(offset + 44, 0.0)
		
		# Column 3 (position)
		data.encode_float(offset + 48, pos.x)
		data.encode_float(offset + 52, pos.y)
		data.encode_float(offset + 56, pos.z)
		data.encode_float(offset + 60, 1.0)
		
		offset += 64
		
		# velocity_speed (vec4) - 16 bytes
		data.encode_float(offset, vel.x)
		data.encode_float(offset + 4, vel.y)
		data.encode_float(offset + 8, vel.z)
		data.encode_float(offset + 12, speeds[i])
		offset += 16
		
		# state (vec4) - 16 bytes: current_pitch, current_roll, throttle, unused
		data.encode_float(offset, 0.0)  # current_pitch (managed by shader)
		data.encode_float(offset + 4, 0.0)  # current_roll
		data.encode_float(offset + 8, throttles[i])
		data.encode_float(offset + 12, 0.0)
		offset += 16
		
		# inputs (vec4) - 16 bytes: input_pitch, input_roll, input_yaw, delta
		data.encode_float(offset, input_pitches[i])
		data.encode_float(offset + 4, input_rolls[i])
		data.encode_float(offset + 8, input_yaws[i])
		data.encode_float(offset + 12, delta)
		offset += 16
		
		# params_1 (vec4) - 16 bytes
		data.encode_float(offset, max_speed)
		data.encode_float(offset + 4, min_speed)
		data.encode_float(offset + 8, acceleration)
		data.encode_float(offset + 12, drag_factor)
		offset += 16
		
		# params_2 (vec4) - 16 bytes
		data.encode_float(offset + 0, pitch_speed)
		data.encode_float(offset + 4, roll_speed)
		data.encode_float(offset + 8, pitch_acceleration)
		data.encode_float(offset + 12, roll_acceleration)
		offset += 16
		
		# factors (vec4) - 16 bytes
		data.encode_float(offset, engine_factors[i])
		data.encode_float(offset + 4, lift_factors[i])
		data.encode_float(offset + 8, 1.0)  # h_tail_factor
		data.encode_float(offset + 12, roll_authorities[i])
		offset += 16
		
		# factors_2 (vec4) - 16 bytes
		data.encode_float(offset, 0.0)  # wing_imbalance
		data.encode_float(offset + 4, 1.0)  # v_tail_factor
		data.encode_float(offset + 8, 0.0)
		data.encode_float(offset + 12, 0.0)
	
	return data

func _unpack_aircraft_data(buffer: PackedByteArray) -> void:
	for i in range(MAX_AIRCRAFT):
		if states[i] == 0:
			continue
		
		var offset = i * STRUCT_SIZE
		
		# Read back position from transform (Column 3)
		positions[i] = Vector3(
			buffer.decode_float(offset + 48),
			buffer.decode_float(offset + 52),
			buffer.decode_float(offset + 56)
		)
		
		# Read back basis for rotation update
		var basis_x = Vector3(
			buffer.decode_float(offset + 0),
			buffer.decode_float(offset + 4),
			buffer.decode_float(offset + 8)
		)
		var basis_y = Vector3(
			buffer.decode_float(offset + 16),
			buffer.decode_float(offset + 20),
			buffer.decode_float(offset + 24)
		)
		var basis_z = Vector3(
			buffer.decode_float(offset + 32),
			buffer.decode_float(offset + 36),
			buffer.decode_float(offset + 40)
		)
		var basis = Basis(basis_x, basis_y, basis_z)
		rotations[i] = basis.get_euler()
		
		# Read velocity and speed
		var vel_offset = offset + 64
		velocities[i] = Vector3(
			buffer.decode_float(vel_offset),
			buffer.decode_float(vel_offset + 4),
			buffer.decode_float(vel_offset + 8)
		)
		speeds[i] = buffer.decode_float(vel_offset + 12)
		
		# Read throttle from state
		var state_offset = offset + 80
		throttles[i] = buffer.decode_float(state_offset + 8)

func _update_physics_cpu(delta: float) -> void:
	# CPU fallback - simple physics
	for i in range(MAX_AIRCRAFT):
		if states[i] == 0:
			continue
		
		var basis = Basis.from_euler(rotations[i])
		var forward = -basis.z
		var up = basis.y
		
		# Speed update
		var target_speed = lerp(min_speed, max_speed, throttles[i]) * engine_factors[i]
		speeds[i] = move_toward(speeds[i], target_speed, acceleration * delta)
		
		# Apply AI inputs to rotation
		var pitch_delta = input_pitches[i] * pitch_speed * delta
		var roll_delta = input_rolls[i] * roll_speed * delta
		
		# Rotate basis
		basis = basis.rotated(basis.x, pitch_delta)  # Pitch
		basis = basis.rotated(basis.z, roll_delta)   # Roll
		basis = basis.orthonormalized()
		
		# Update rotation
		rotations[i] = basis.get_euler()
		
		# Update forward/up after rotation
		forward = -basis.z
		up = basis.y
		
		# Velocity calculation
		velocities[i] = forward * speeds[i]
		velocities[i] += up * (speeds[i] * lift_factor * lift_factors[i] * delta)
		velocities[i].y -= 9.8 * delta  # Gravity
		
		# Update position
		positions[i] += velocities[i] * delta
		
		# Keep above ground
		if positions[i].y < 10.0:
			positions[i].y = 10.0
			velocities[i].y = 0.0

func _update_rendering() -> void:
	# Get camera position and frustum for LOD and culling
	var camera = get_viewport().get_camera_3d()
	var camera_pos = _get_camera_position()
	
	# Frustum culling data
	var camera_forward = Vector3.FORWARD
	if camera:
		camera_forward = -camera.global_transform.basis.z
	
	# LOD arrays
	var ally_high: Array[Transform3D] = []
	var ally_med: Array[Transform3D] = []
	var ally_low: Array[Transform3D] = []
	var enemy_high: Array[Transform3D] = []
	var enemy_med: Array[Transform3D] = []
	var enemy_low: Array[Transform3D] = []
	
	const MAX_RENDER_DIST_SQ: float = 100000000.0  # 10km
	const FRUSTUM_DOT_THRESHOLD: float = -0.3  # ~120° FOV
	
	for i in range(MAX_AIRCRAFT):
		if states[i] == 0:
			continue
		
		var pos = positions[i]
		
		# Distance culling
		var to_aircraft = pos - camera_pos
		var dist_sq = to_aircraft.length_squared()
		
		if dist_sq > MAX_RENDER_DIST_SQ:
			continue  # Too far, cull
		
		# Frustum culling (rough approximation)
		if dist_sq > 1000.0:  # Only cull if not very close
			var dir_normalized = to_aircraft.normalized()
			var dot = dir_normalized.dot(camera_forward)
			
			if dot < FRUSTUM_DOT_THRESHOLD:
				continue  # Behind camera, cull
		
		# Passed culling - determine LOD
		var basis = Basis.from_euler(rotations[i])
		var transform = Transform3D(basis, pos)
		
		var is_ally = teams[i] == GlobalEnums.Team.ALLY
		
		if dist_sq < LOD_HIGH_DIST_SQ:  # < 500m
			if is_ally:
				ally_high.append(transform)
			else:
				enemy_high.append(transform)
		elif dist_sq < LOD_MEDIUM_DIST_SQ:  # 500-2000m
			if is_ally:
				ally_med.append(transform)
			else:
				enemy_med.append(transform)
		else:  # > 2000m
			if is_ally:
				ally_low.append(transform)
			else:
				enemy_low.append(transform)
	
	# Update all LOD MultiMeshes
	_update_lod_multimesh(_multimesh_ally_high, ally_high)
	_update_lod_multimesh(_multimesh_ally_med, ally_med)
	_update_lod_multimesh(_multimesh_ally_low, ally_low)
	_update_lod_multimesh(_multimesh_enemy_high, enemy_high)
	_update_lod_multimesh(_multimesh_enemy_med, enemy_med)
	_update_lod_multimesh(_multimesh_enemy_low, enemy_low)

func _get_camera_position() -> Vector3:
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		return player.global_position
	
	var camera = get_viewport().get_camera_3d()
	if camera:
		return camera.global_position
	
	return Vector3.ZERO

func _update_lod_multimesh(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	var mm = mmi.multimesh
	var count = mini(transforms.size(), MAX_AIRCRAFT)
	
	for i in range(count):
		mm.set_instance_transform(i, transforms[i])
	
	mm.visible_instance_count = count
