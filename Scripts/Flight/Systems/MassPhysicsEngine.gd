extends Node
class_name MassPhysicsEngine

# GPU Compute Shader
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _uniform_set: RID
var _buffer: RID
var _use_compute_shader: bool = false
var _gpu_task_pending: bool = false

const STRUCT_SIZE: int = 176  # bytes per aircraft in GPU buffer

var _mass_system: MassAircraftSystem
var _max_instances: int = 0

func initialize(mass_system: MassAircraftSystem, max_instances: int) -> void:
	_mass_system = mass_system
	_max_instances = max_instances
	_initialize_compute_shader()

func _exit_tree() -> void:
	_cleanup_gpu_resources()

func _initialize_compute_shader() -> void:
	# Try to create RenderingDevice (only works with Vulkan backend)
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_warning("[MassPhysicsEngine] Compute shaders not available (requires Vulkan). Using CPU fallback.")
		_use_compute_shader = false
		return
	
	# Load compute shader
	var shader_file = load("res://Assets/Shaders/Compute/aerodynamics.glsl")
	if not shader_file:
		push_warning("[MassPhysicsEngine] Compute shader not found. Using CPU fallback.")
		_use_compute_shader = false
		return
	
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	
	# Create GPU buffer
	var buffer_size = _max_instances * STRUCT_SIZE
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
	print("[MassPhysicsEngine] Compute shader initialized successfully")

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

func update_physics(delta: float) -> void:
	if not _mass_system:
		return
		
	if _use_compute_shader:
		_update_physics_gpu(delta)
	else:
		_update_physics_cpu(delta)

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
	var active_count = _mass_system.active_count
	if active_count > 0:
		var workgroups = ceili(float(active_count) / 64.0)
		_rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
	
	_rd.compute_list_end()
	
	# 4. Submit but DO NOT sync immediately
	_rd.submit()
	_gpu_task_pending = true

func _pack_aircraft_data(delta: float) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(_max_instances * STRUCT_SIZE)
	
	# Cache variables for speed
	var states = _mass_system.states
	var positions = _mass_system.positions
	var velocities = _mass_system.velocities
	var rotations = _mass_system.rotations
	var speeds = _mass_system.speeds
	var throttles = _mass_system.throttles
	
	var input_pitches = _mass_system.input_pitches
	var input_rolls = _mass_system.input_rolls
	var input_yaws = _mass_system.input_yaws
	
	var engine_factors = _mass_system.engine_factors
	var lift_factors = _mass_system.lift_factors
	var roll_authorities = _mass_system.roll_authorities
	
	# Parameters
	var max_speed = _mass_system.max_speed
	var min_speed = _mass_system.min_speed
	var acceleration = _mass_system.acceleration
	var drag_factor = _mass_system.drag_factor
	var pitch_speed = _mass_system.pitch_speed
	var roll_speed = _mass_system.roll_speed
	var pitch_accel = _mass_system.pitch_acceleration
	var roll_accel = _mass_system.roll_acceleration
	
	for i in range(_max_instances):
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
		data.encode_float(offset + 8, pitch_accel)
		data.encode_float(offset + 12, roll_accel)
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
	for i in range(_max_instances):
		if _mass_system.states[i] == 0:
			continue
		
		var offset = i * STRUCT_SIZE
		
		# Read back position from transform (Column 3)
		_mass_system.positions[i] = Vector3(
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
		_mass_system.rotations[i] = basis.get_euler()
		
		# Read velocity and speed
		var vel_offset = offset + 64
		_mass_system.velocities[i] = Vector3(
			buffer.decode_float(vel_offset),
			buffer.decode_float(vel_offset + 4),
			buffer.decode_float(vel_offset + 8)
		)
		_mass_system.speeds[i] = buffer.decode_float(vel_offset + 12)
		
		# Read throttle from state
		var state_offset = offset + 80
		_mass_system.throttles[i] = buffer.decode_float(state_offset + 8)

func _update_physics_cpu(delta: float) -> void:
	# CPU fallback - simple physics
	
	# Cache array refs
	var states = _mass_system.states
	var positions = _mass_system.positions
	var velocities = _mass_system.velocities
	var rotations = _mass_system.rotations
	var speeds = _mass_system.speeds
	var throttles = _mass_system.throttles
	var engine_factors = _mass_system.engine_factors
	var lift_factors = _mass_system.lift_factors
	var input_pitches = _mass_system.input_pitches
	var input_rolls = _mass_system.input_rolls
	
	for i in range(_max_instances):
		if states[i] == 0:
			continue
		
		var basis = Basis.from_euler(rotations[i])
		var forward = -basis.z
		var up = basis.y
		
		# Speed update
		var target_speed = lerp(_mass_system.min_speed, _mass_system.max_speed, throttles[i]) * engine_factors[i]
		speeds[i] = move_toward(speeds[i], target_speed, _mass_system.acceleration * delta)
		
		# Apply AI inputs to rotation
		var pitch_delta = input_pitches[i] * _mass_system.pitch_speed * delta
		var roll_delta = input_rolls[i] * _mass_system.roll_speed * delta
		
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
		velocities[i] += up * (speeds[i] * _mass_system.lift_factor * lift_factors[i] * delta)
		velocities[i].y -= 9.8 * delta  # Gravity
		
		# Update position
		positions[i] += velocities[i] * delta
		
		# Keep above ground
		if positions[i].y < 10.0:
			positions[i].y = 10.0
			velocities[i].y = 0.0
