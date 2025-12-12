extends Node

class_name FlightManager

static var instance: FlightManager

var aircrafts: Array[Node] = []
var ai_controllers: Array[Node] = []

# Thread-Safe Cache
var _aircraft_data_map: Dictionary = {}
var _allies_list: Array[Dictionary] = []
var _enemies_list: Array[Dictionary] = []
var _team_lists_dirty: bool = true  # Flag to rebuild team lists only when needed
var _frame_count: int = 0
var _ai_task_group_id: int = -1
var _thread_count: int = 1

# Reusable Physics Query
var _query_params: PhysicsRayQueryParameters3D

# Object Pooling & MultiMesh
class ProjectileData:
	var position: Vector3
	var velocity: Vector3
	var life: float
	var damage: float = 10.0
	var basis: Basis # Cache rotation to avoid recalculating every frame
	var spawn_time: float # For shader

var _projectile_data: Array[ProjectileData] = []
var _projectile_pool: Array[ProjectileData] = []
var _multi_mesh_instance: MultiMeshInstance3D
var _max_projectiles: int = 10000
var _shader_material: ShaderMaterial

# Missile Pooling
var _missile_pool: Array[Node] = []
var _missile_scene = preload("res://Scenes/Entities/Missile.tscn")

# --- Compute Shader (Aircraft) ---
var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID

# Double buffering for async compute
var buffer_rid_write: RID  # Current frame write
var buffer_rid_read: RID   # Previous frame read
var uniform_set_write: RID
var uniform_set_read: RID

var _buffer_capacity: int = 1024
var _byte_array_write: PackedByteArray
var _byte_array_read: PackedByteArray
var _buffer_writer: StreamPeerBuffer  # Reuse buffer writer
var _buffer_reader: StreamPeerBuffer  # Reuse buffer reader
var _aircraft_positions: PackedVector3Array = PackedVector3Array()  # Thread-safe position cache
var _compute_submitted: bool = false  # Track if compute was submitted

# --- Compute Shader (Missile) ---
var missile_shader_rid: RID
var missile_pipeline: RID

# Double buffering for missile async compute
var missile_buffer_rid_write: RID
var missile_buffer_rid_read: RID
var missile_uniform_set_write: RID
var missile_uniform_set_read: RID

var _missile_buffer_capacity: int = 256
var _missile_byte_array_write: PackedByteArray
var _missile_byte_array_read: PackedByteArray
var _missile_buffer_writer: StreamPeerBuffer
var _missile_buffer_reader: StreamPeerBuffer
var _missile_compute_submitted: bool = false
var active_missiles: Array[Node] = []

func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	# Reserve 1 core for Main Thread/Audio to prevent starvation (WASAPI errors)
	_thread_count = max(1, OS.get_processor_count() - 1)
	
	_query_params = PhysicsRayQueryParameters3D.new()
	_query_params.collide_with_areas = false
	_query_params.collide_with_bodies = true
	
	_setup_multimesh()
	_setup_compute()
	_setup_missile_compute()
	_warmup_compute_shaders()

func _warmup_compute_shaders() -> void:
	if not rd:
		return
	
	# Warm up aircraft shader
	if pipeline.is_valid() and uniform_set_write.is_valid():
		var compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_write, 0)
		rd.compute_list_dispatch(compute_list, 1, 1, 1)
		rd.compute_list_end()
		rd.submit()
		rd.sync()  # Force compilation now
	
	# Warm up missile shader
	if missile_pipeline.is_valid() and missile_uniform_set_write.is_valid():
		var compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, missile_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, missile_uniform_set_write, 0)
		rd.compute_list_dispatch(compute_list, 1, 1, 1)
		rd.compute_list_end()
		rd.submit()
		rd.sync()  # Force compilation now

func _setup_multimesh() -> void:
	_multi_mesh_instance = MultiMeshInstance3D.new()
	add_child(_multi_mesh_instance)
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false # We use custom_data instead
	mm.use_custom_data = true # Enable custom data for shader
	mm.instance_count = _max_projectiles
	mm.visible_instance_count = 0
	
	# Create Mesh (Capsule)
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.5
	
	# Load Shader
	var shader = load("res://Assets/Shaders/projectile.gdshader")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	
	mesh.material = _shader_material
	
	mm.mesh = mesh
	_multi_mesh_instance.multimesh = mm

func _setup_compute() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		push_error("Failed to create RenderingDevice")
		return
		
	var shader_file = load("res://Assets/Shaders/Compute/aerodynamics.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader_rid)
	
	# Pre-allocate buffer for expected aircraft count (avoid runtime reallocation)
	_resize_buffer(512)  # Adjust based on expected max aircraft

func _setup_missile_compute() -> void:
	if not rd: return
	
	var shader_file = load("res://Assets/Shaders/Compute/missile_physics.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	missile_shader_rid = rd.shader_create_from_spirv(shader_spirv)
	missile_pipeline = rd.compute_pipeline_create(missile_shader_rid)
	
	# Pre-allocate buffer for expected missile count
	_resize_missile_buffer(128)

func _resize_missile_buffer(new_capacity: int) -> void:
	if missile_uniform_set_write.is_valid():
		rd.free_rid(missile_uniform_set_write)
	if missile_uniform_set_read.is_valid():
		rd.free_rid(missile_uniform_set_read)
	if missile_buffer_rid_write.is_valid():
		rd.free_rid(missile_buffer_rid_write)
	if missile_buffer_rid_read.is_valid():
		rd.free_rid(missile_buffer_rid_read)
	
	_missile_buffer_capacity = new_capacity
	# Struct size = 128 bytes (mat4 + 4 vec4s)
	var size = _missile_buffer_capacity * 128
	
	# Create write buffer
	_missile_byte_array_write = PackedByteArray()
	_missile_byte_array_write.resize(size)
	missile_buffer_rid_write = rd.storage_buffer_create(size, _missile_byte_array_write)
	
	# Create read buffer
	_missile_byte_array_read = PackedByteArray()
	_missile_byte_array_read.resize(size)
	missile_buffer_rid_read = rd.storage_buffer_create(size, _missile_byte_array_read)
	
	# Create uniform sets
	var uniform_write = RDUniform.new()
	uniform_write.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_write.binding = 0
	uniform_write.add_id(missile_buffer_rid_write)
	missile_uniform_set_write = rd.uniform_set_create([uniform_write], missile_shader_rid, 0)
	
	var uniform_read = RDUniform.new()
	uniform_read.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_read.binding = 0
	uniform_read.add_id(missile_buffer_rid_read)
	missile_uniform_set_read = rd.uniform_set_create([uniform_read], missile_shader_rid, 0)


func _resize_buffer(new_capacity: int) -> void:
	# Free old uniform sets and buffers
	if uniform_set_write.is_valid():
		rd.free_rid(uniform_set_write)
	if uniform_set_read.is_valid():
		rd.free_rid(uniform_set_read)
	if buffer_rid_write.is_valid():
		rd.free_rid(buffer_rid_write)
	if buffer_rid_read.is_valid():
		rd.free_rid(buffer_rid_read)
	
	_buffer_capacity = new_capacity
	# Struct size = 176 bytes (mat4 + 7 vec4s)
	var size = _buffer_capacity * 176
	
	# Create write buffer
	_byte_array_write = PackedByteArray()
	_byte_array_write.resize(size)
	buffer_rid_write = rd.storage_buffer_create(size, _byte_array_write)
	
	# Create read buffer
	_byte_array_read = PackedByteArray()
	_byte_array_read.resize(size)
	buffer_rid_read = rd.storage_buffer_create(size, _byte_array_read)
	
	# Create uniform sets
	var uniform_write = RDUniform.new()
	uniform_write.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_write.binding = 0
	uniform_write.add_id(buffer_rid_write)
	uniform_set_write = rd.uniform_set_create([uniform_write], shader_rid, 0)
	
	var uniform_read = RDUniform.new()
	uniform_read.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_read.binding = 0
	uniform_read.add_id(buffer_rid_read)
	uniform_set_read = rd.uniform_set_create([uniform_read], shader_rid, 0)

func _exit_tree() -> void:
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
	
	if rd:
		# Free dependents first (UniformSets -> Buffers, Pipelines -> Shaders)
		if uniform_set_write.is_valid(): rd.free_rid(uniform_set_write)
		if uniform_set_read.is_valid(): rd.free_rid(uniform_set_read)
		if buffer_rid_write.is_valid(): rd.free_rid(buffer_rid_write)
		if buffer_rid_read.is_valid(): rd.free_rid(buffer_rid_read)
		if pipeline.is_valid(): rd.free_rid(pipeline)
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		
		if missile_uniform_set_write.is_valid(): rd.free_rid(missile_uniform_set_write)
		if missile_uniform_set_read.is_valid(): rd.free_rid(missile_uniform_set_read)
		if missile_buffer_rid_write.is_valid(): rd.free_rid(missile_buffer_rid_write)
		if missile_buffer_rid_read.is_valid(): rd.free_rid(missile_buffer_rid_read)
		if missile_pipeline.is_valid(): rd.free_rid(missile_pipeline)
		if missile_shader_rid.is_valid(): rd.free_rid(missile_shader_rid)
		
		rd.free()
		rd = null # Prevent double free
		
	if instance == self:
		instance = null

func register_aircraft(a: Node) -> void:
	if a not in aircrafts:
		aircrafts.append(a)
		_team_lists_dirty = true

func unregister_aircraft(a: Node) -> void:
	aircrafts.erase(a)
	_team_lists_dirty = true
	
	if is_instance_valid(a):
		var id = a.get_instance_id()
		_aircraft_data_map.erase(id)

func register_ai(ai: Node) -> void:
	if ai not in ai_controllers:
		ai_controllers.append(ai)

func unregister_ai(ai: Node) -> void:
	ai_controllers.erase(ai)

func spawn_projectile(tf: Transform3D) -> void:
	if _projectile_data.size() >= _max_projectiles:
		return
		
	var p: ProjectileData
	if _projectile_pool.is_empty():
		p = ProjectileData.new()
	else:
		p = _projectile_pool.pop_back()
	
	var forward = -tf.basis.z
	p.position = tf.origin
	p.velocity = forward * 200.0
	p.life = 2.0
	p.damage = 10.0
	p.spawn_time = Time.get_ticks_msec() / 1000.0
	
	# Calculate basis for projectile orientation
	# Safety check: Ensure forward is valid
	if forward.is_zero_approx() or not forward.is_normalized():
		forward = -Vector3.FORWARD
	
	var up = Vector3.UP
	var forward_dot = abs(forward.y)
	if forward_dot > 0.99:
		up = Vector3.RIGHT
	p.basis = Basis.looking_at(forward, up).rotated(Vector3.RIGHT, -PI/2)
	
	_projectile_data.append(p)
	
	var mm = _multi_mesh_instance.multimesh
	var idx = _projectile_data.size() - 1
	mm.visible_instance_count = idx + 1
	mm.set_instance_transform(idx, Transform3D(p.basis, p.position))
	mm.set_instance_custom_data(idx, Color(p.velocity.x, p.velocity.y, p.velocity.z, p.spawn_time))

func return_projectile(p: Node) -> void:
	if is_instance_valid(p):
		p.queue_free()

func spawn_missile(tf: Transform3D, target: Node3D, shooter: Node3D) -> void:
	var m: Missile
	if _missile_pool.is_empty():
		m = _missile_scene.instantiate() as Missile
		get_tree().current_scene.add_child(m)
	else:
		m = _missile_pool.pop_back() as Missile
		if not is_instance_valid(m):
			m = _missile_scene.instantiate() as Missile
			get_tree().current_scene.add_child(m)
	
	m.launch(tf, target, shooter)

func return_missile(m: Missile) -> void:
	if is_instance_valid(m):
		m.hide()
		m.set_physics_process(false)
		m.set_deferred("monitoring", false)
		m.set_deferred("monitorable", false)
		m.global_position = Vector3(0, -1000, 0)
		_missile_pool.append(m)

func get_aircraft_data(node: Node) -> Dictionary:
	if not is_instance_valid(node): return {}
	var id = node.get_instance_id()
	if _aircraft_data_map.has(id):
		return _aircraft_data_map[id]
	return {}

func get_aircraft_data_by_id(id: int) -> Dictionary:
	if _aircraft_data_map.has(id):
		return _aircraft_data_map[id]
	return {}

func get_enemies_of(team: int) -> Array[Dictionary]:
	if team == GlobalEnums.Team.ALLY:
		return _enemies_list
	elif team == GlobalEnums.Team.ENEMY:
		return _allies_list
	return []

func _physics_process(delta: float) -> void:
	_frame_count += 1
	
	# Early exit if no work to do
	var aircraft_count = aircrafts.size()
	if aircraft_count == 0:
		_multi_mesh_instance.multimesh.visible_instance_count = 0
		return
	
	# Update cache every frame (lightweight now)
	_update_cache()
	
	# Start AI processing less frequently (every 2 physics frames)
	var ai_count = ai_controllers.size()
	if ai_count > 0 and (_frame_count & 1) == 0:
		# Wait for previous AI tasks only if they exist (moved here to avoid blocking early)
		if _ai_task_group_id != -1:
			WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
			_ai_task_group_id = -1
		
		var task_count = min(ai_count, _thread_count)
		_ai_task_group_id = WorkerThreadPool.add_group_task(
			_process_ai_batch.bind(delta * 2.0, ai_count, task_count),  # delta * 2 because we skip frames
			task_count,
			-1,
			true,
			"AI Logic"
		)
	
	# Compute Shader Physics (Aircraft) - Async with Double Buffering
	# Read from previous frame, write to current frame
	if rd:
		# Wait for previous GPU work to complete before starting new frame
		if _compute_submitted:
			rd.sync()
		
		# Read results from PREVIOUS frame (if available)
		if _compute_submitted:
			if not _buffer_reader:
				_buffer_reader = StreamPeerBuffer.new()
			_buffer_reader.data_array = rd.buffer_get_data(buffer_rid_read)
			
			var off_read = 0
			for a in aircrafts:
				if not is_instance_valid(a):
					off_read += 176
					continue
				
				_buffer_reader.seek(off_read)
				
				# Read transform
				var bx_x = _buffer_reader.get_float(); var bx_y = _buffer_reader.get_float(); var bx_z = _buffer_reader.get_float(); _buffer_reader.get_float()
				var by_x = _buffer_reader.get_float(); var by_y = _buffer_reader.get_float(); var by_z = _buffer_reader.get_float(); _buffer_reader.get_float()
				var bz_x = _buffer_reader.get_float(); var bz_y = _buffer_reader.get_float(); var bz_z = _buffer_reader.get_float(); _buffer_reader.get_float()
				_buffer_reader.get_float(); _buffer_reader.get_float(); _buffer_reader.get_float(); _buffer_reader.get_float()
				
				# Read state
				var vx = _buffer_reader.get_float(); var vy = _buffer_reader.get_float(); var vz = _buffer_reader.get_float(); var new_speed = _buffer_reader.get_float()
				var new_pitch = _buffer_reader.get_float(); var new_roll = _buffer_reader.get_float()
				
				# Validate and apply - Enhanced validation
				var new_basis_x = Vector3(bx_x, bx_y, bx_z)
				var new_basis_y = Vector3(by_x, by_y, by_z)
				var new_basis_z = Vector3(bz_x, bz_y, bz_z)
				
				if new_basis_x.is_finite() and new_basis_y.is_finite() and new_basis_z.is_finite():
					var new_basis = Basis(new_basis_x, new_basis_y, new_basis_z)
					var det = new_basis.determinant()
					
					# Only apply if basis is valid (determinant != 0)
					if abs(det) > 0.001:
						a.global_basis = new_basis
						a.velocity = Vector3(vx, vy, vz)
						a.current_speed = new_speed
						a.current_pitch = new_pitch
						a.current_roll = new_roll
				
				off_read += 176
		
		# Resize if needed
		if aircraft_count > _buffer_capacity:
			_resize_buffer(aircraft_count + 128)
		
		# Write input data for CURRENT frame
		if not _buffer_writer:
			_buffer_writer = StreamPeerBuffer.new()
		_buffer_writer.data_array = _byte_array_write
		
		var offset = 0
		for a in aircrafts:
			if not is_instance_valid(a): continue
			
			var tf = a.global_transform
			var basis = tf.basis
			var origin = tf.origin
			var vel = a.velocity
			
			_buffer_writer.seek(offset)
			# Transform (64 bytes)
			_buffer_writer.put_float(basis.x.x); _buffer_writer.put_float(basis.x.y); _buffer_writer.put_float(basis.x.z); _buffer_writer.put_float(0.0)
			_buffer_writer.put_float(basis.y.x); _buffer_writer.put_float(basis.y.y); _buffer_writer.put_float(basis.y.z); _buffer_writer.put_float(0.0)
			_buffer_writer.put_float(basis.z.x); _buffer_writer.put_float(basis.z.y); _buffer_writer.put_float(basis.z.z); _buffer_writer.put_float(0.0)
			_buffer_writer.put_float(origin.x); _buffer_writer.put_float(origin.y); _buffer_writer.put_float(origin.z); _buffer_writer.put_float(1.0)
			
			# State (112 bytes)
			_buffer_writer.put_float(vel.x); _buffer_writer.put_float(vel.y); _buffer_writer.put_float(vel.z); _buffer_writer.put_float(a.current_speed)
			_buffer_writer.put_float(a.current_pitch); _buffer_writer.put_float(a.current_roll); _buffer_writer.put_float(a.throttle); _buffer_writer.put_float(0.0)
			_buffer_writer.put_float(a.input_pitch); _buffer_writer.put_float(a.input_roll); _buffer_writer.put_float(0.0); _buffer_writer.put_float(delta)
			_buffer_writer.put_float(a.max_speed); _buffer_writer.put_float(a.min_speed); _buffer_writer.put_float(a.acceleration); _buffer_writer.put_float(a.drag_factor)
			_buffer_writer.put_float(a.pitch_speed); _buffer_writer.put_float(a.roll_speed); _buffer_writer.put_float(a.pitch_acceleration); _buffer_writer.put_float(a.roll_acceleration)
			_buffer_writer.put_float(a._c_engine_factor); _buffer_writer.put_float(a._c_lift_factor); _buffer_writer.put_float(a._c_h_tail_factor); _buffer_writer.put_float(a._c_roll_authority)
			_buffer_writer.put_float(a._c_wing_imbalance); _buffer_writer.put_float(a._c_v_tail_factor); _buffer_writer.put_float(0.0); _buffer_writer.put_float(0.0)
			
			offset += 176

		# Submit compute for CURRENT frame (non-blocking)
		rd.buffer_update(buffer_rid_write, 0, offset, _buffer_writer.data_array)
		
		var compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_write, 0)
		rd.compute_list_dispatch(compute_list, int(ceil(aircraft_count / 64.0)), 1, 1)
		rd.compute_list_end()
		
		rd.submit()
		# Sync happens at START of next frame (async pattern)
		
		# Swap buffers for next frame
		var temp_rid = buffer_rid_write
		buffer_rid_write = buffer_rid_read
		buffer_rid_read = temp_rid
		
		var temp_uniform = uniform_set_write
		uniform_set_write = uniform_set_read
		uniform_set_read = temp_uniform
		
		var temp_array = _byte_array_write
		_byte_array_write = _byte_array_read
		_byte_array_read = temp_array
		
		_compute_submitted = true

	# Missile Compute Shader Physics - Async with Double Buffering
	var missile_count = active_missiles.size()
	if missile_count > 0 and rd:
		# Wait for ALL previous GPU work to complete before starting new compute
		# This includes both previous missile work AND current frame aircraft work
		rd.sync()
		
		# Read results from PREVIOUS frame (if available)
		if _missile_compute_submitted:
			if not _missile_buffer_reader:
				_missile_buffer_reader = StreamPeerBuffer.new()
			_missile_buffer_reader.data_array = rd.buffer_get_data(missile_buffer_rid_read)
			
			var m_off_read = 0
			for i in range(missile_count - 1, -1, -1):
				var m = active_missiles[i]
				if not is_instance_valid(m):
					m_off_read += 128
					continue
				
				_missile_buffer_reader.seek(m_off_read)
				
				# Read transform
				var bx_x = _missile_buffer_reader.get_float(); var bx_y = _missile_buffer_reader.get_float(); var bx_z = _missile_buffer_reader.get_float(); _missile_buffer_reader.get_float()
				var by_x = _missile_buffer_reader.get_float(); var by_y = _missile_buffer_reader.get_float(); var by_z = _missile_buffer_reader.get_float(); _missile_buffer_reader.get_float()
				var bz_x = _missile_buffer_reader.get_float(); var bz_y = _missile_buffer_reader.get_float(); var bz_z = _missile_buffer_reader.get_float(); _missile_buffer_reader.get_float()
				var ox = _missile_buffer_reader.get_float(); var oy = _missile_buffer_reader.get_float(); var oz = _missile_buffer_reader.get_float(); _missile_buffer_reader.get_float()
				
				# Read state
				var vx = _missile_buffer_reader.get_float(); var vy = _missile_buffer_reader.get_float(); var vz = _missile_buffer_reader.get_float(); var new_speed = _missile_buffer_reader.get_float()
				_missile_buffer_reader.get_float(); _missile_buffer_reader.get_float(); _missile_buffer_reader.get_float(); var new_life = _missile_buffer_reader.get_float()
				_missile_buffer_reader.get_float(); _missile_buffer_reader.get_float(); _missile_buffer_reader.get_float(); _missile_buffer_reader.get_float()
				var state = _missile_buffer_reader.get_float()
				
				if state > 0.5:
					m.explode()
				else:
					var new_origin = Vector3(ox, oy, oz)
					if new_origin.is_finite() and new_origin.length_squared() < 1e14:
						var new_basis = Basis(Vector3(bx_x, bx_y, bx_z), Vector3(by_x, by_y, by_z), Vector3(bz_x, bz_y, bz_z))
						m.update_from_compute(Transform3D(new_basis, new_origin), Vector3(vx, vy, vz), new_speed, new_life)
				
				m_off_read += 128
		
		# Resize if needed
		if missile_count > _missile_buffer_capacity:
			_resize_missile_buffer(missile_count + 64)
		
		# Write input data for CURRENT frame
		if not _missile_buffer_writer:
			_missile_buffer_writer = StreamPeerBuffer.new()
		_missile_buffer_writer.data_array = _missile_byte_array_write
		
		var m_offset = 0
		for m in active_missiles:
			if not is_instance_valid(m): continue
			
			var tf = m.global_transform
			var basis = tf.basis
			var origin = tf.origin
			var vel = m.velocity
			var target_pos = Vector3.ZERO
			var has_target = 0.0
			if is_instance_valid(m.target):
				target_pos = m.target.global_position
				has_target = 1.0
			
			_missile_buffer_writer.seek(m_offset)
			# Transform (64 bytes)
			_missile_buffer_writer.put_float(basis.x.x); _missile_buffer_writer.put_float(basis.x.y); _missile_buffer_writer.put_float(basis.x.z); _missile_buffer_writer.put_float(0.0)
			_missile_buffer_writer.put_float(basis.y.x); _missile_buffer_writer.put_float(basis.y.y); _missile_buffer_writer.put_float(basis.y.z); _missile_buffer_writer.put_float(0.0)
			_missile_buffer_writer.put_float(basis.z.x); _missile_buffer_writer.put_float(basis.z.y); _missile_buffer_writer.put_float(basis.z.z); _missile_buffer_writer.put_float(0.0)
			_missile_buffer_writer.put_float(origin.x); _missile_buffer_writer.put_float(origin.y); _missile_buffer_writer.put_float(origin.z); _missile_buffer_writer.put_float(1.0)
			
			# State (64 bytes)
			_missile_buffer_writer.put_float(vel.x); _missile_buffer_writer.put_float(vel.y); _missile_buffer_writer.put_float(vel.z); _missile_buffer_writer.put_float(m.speed)
			_missile_buffer_writer.put_float(target_pos.x); _missile_buffer_writer.put_float(target_pos.y); _missile_buffer_writer.put_float(target_pos.z); _missile_buffer_writer.put_float(m._current_life)
			_missile_buffer_writer.put_float(m.max_speed); _missile_buffer_writer.put_float(m.acceleration); _missile_buffer_writer.put_float(m.turn_speed); _missile_buffer_writer.put_float(m.lifetime)
			_missile_buffer_writer.put_float(0.0); _missile_buffer_writer.put_float(has_target); _missile_buffer_writer.put_float(delta); _missile_buffer_writer.put_float(m.proximity_radius)
			
			m_offset += 128

		# Submit compute for CURRENT frame (non-blocking)
		rd.buffer_update(missile_buffer_rid_write, 0, m_offset, _missile_buffer_writer.data_array)
		
		var compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, missile_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, missile_uniform_set_write, 0)
		var groups = ceil(missile_count / 64.0)
		rd.compute_list_dispatch(compute_list, int(groups), 1, 1)
		rd.compute_list_end()
		
		rd.submit()
		# Sync happens at START of next frame (async pattern)
		
		# Swap buffers for next frame
		var temp_m_rid = missile_buffer_rid_write
		missile_buffer_rid_write = missile_buffer_rid_read
		missile_buffer_rid_read = temp_m_rid
		
		var temp_m_uniform = missile_uniform_set_write
		missile_uniform_set_write = missile_uniform_set_read
		missile_uniform_set_read = temp_m_uniform
		
		var temp_m_array = _missile_byte_array_write
		_missile_byte_array_write = _missile_byte_array_read
		_missile_byte_array_read = temp_m_array
		
		_missile_compute_submitted = true

	# Projectile Movement
	var proj_count = _projectile_data.size()
	if proj_count == 0:
		_multi_mesh_instance.multimesh.visible_instance_count = 0
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	_shader_material.set_shader_parameter("current_time", current_time)
	
	var space_state = aircrafts[0].get_world_3d().direct_space_state if aircraft_count > 0 and is_instance_valid(aircrafts[0]) else null
	if not space_state:
		return
	
	var query = _query_params
	var mm = _multi_mesh_instance.multimesh
	var i = 0
	
	# Only do expensive raycasts every 2 frames
	var do_raycast = (_frame_count & 1) == 0
	
	while i < _projectile_data.size():
		var p = _projectile_data[i]
		p.life -= delta
		
		if p.life <= 0:
			# Dead - recycle
			_projectile_pool.append(p)
			var last_idx = _projectile_data.size() - 1
			if i != last_idx:
				_projectile_data[i] = _projectile_data[last_idx]
				mm.set_instance_transform(i, mm.get_instance_transform(last_idx))
				mm.set_instance_custom_data(i, mm.get_instance_custom_data(last_idx))
			_projectile_data.pop_back()
		else:
			var movement = p.velocity * delta
			
			# Ray cast (skip every other frame for performance)
			if do_raycast:
				var from = p.position
				query.from = from
				query.to = from + movement
				var result = space_state.intersect_ray(query)
				
				if not result.is_empty():
					# Hit something
					var collider = result.collider
					if is_instance_valid(collider) and collider.has_method("take_damage"):
						collider.take_damage(p.damage, collider.to_local(result.position))
					# Recycle
					_projectile_pool.append(p)
					var last_idx = _projectile_data.size() - 1
					if i != last_idx:
						_projectile_data[i] = _projectile_data[last_idx]
						mm.set_instance_transform(i, mm.get_instance_transform(last_idx))
						mm.set_instance_custom_data(i, mm.get_instance_custom_data(last_idx))
					_projectile_data.pop_back()
					continue
			
			# Still alive - update position
			p.position += movement
			i += 1
	
	mm.visible_instance_count = _projectile_data.size()

func _update_cache() -> void:
	# Resize position cache to match aircraft count
	var aircraft_count = aircrafts.size()
	if _aircraft_positions.size() != aircraft_count:
		_aircraft_positions.resize(aircraft_count)
		_team_lists_dirty = true
	
	# Only update expensive transform cache every 2 frames for non-player aircraft
	var update_all = (_frame_count & 1) == 0
	
	for i in range(aircraft_count):
		var a = aircrafts[i]
		if not is_instance_valid(a):
			_aircraft_positions[i] = Vector3.ZERO
			continue
		
		var id = a.get_instance_id()
		var data = _aircraft_data_map.get(id)
		
		# Always update player and on update_all frames, or create initial data
		var should_update_transform = update_all or a.is_player or not data
		
		if should_update_transform:
			var tf = a.global_transform  # Only access when needed
			
			if a.has_method("prepare_for_threads_with_transform"):
				a.prepare_for_threads_with_transform(tf)
			
			# Cache position for thread-safe access
			_aircraft_positions[i] = tf.origin
			
			if data:
				# Update existing data
				data.pos = _aircraft_positions[i]
				data.transform = tf
				data.vel = a.velocity
				data.team = a.team
				data.index = i
			else:
				# Create new data
				data = {
					"ref": a,
					"id": id,
					"pos": tf.origin,
					"transform": tf,
					"team": a.team,
					"vel": a.velocity,
					"index": i
				}
				_aircraft_data_map[id] = data
				_team_lists_dirty = true
				_aircraft_positions[i] = tf.origin
	
	# Only rebuild team lists when needed (on aircraft add/remove or team change)
	if _team_lists_dirty:
		_allies_list.clear()
		_enemies_list.clear()
		
		for id in _aircraft_data_map:
			var data = _aircraft_data_map[id]
			var team = data.team
			if team == GlobalEnums.Team.ALLY:
				_allies_list.append(data)
			elif team == GlobalEnums.Team.ENEMY:
				_enemies_list.append(data)
		
		_team_lists_dirty = false

func _process_ai_batch(task_idx: int, delta: float, total_items: int, total_tasks: int) -> void:
	var start_idx = int(float(task_idx * total_items) / total_tasks)
	var end_idx = int(float((task_idx + 1) * total_items) / total_tasks)
	
	# Get player position from cached positions (thread-safe)
	var player_pos = Vector3.ZERO
	var has_player = false
	for i in range(_aircraft_positions.size()):
		if i < aircrafts.size() and is_instance_valid(aircrafts[i]) and aircrafts[i].is_player:
			player_pos = _aircraft_positions[i]
			has_player = true
			break
	
	for i in range(start_idx, min(end_idx, total_items)):
		var ai = ai_controllers[i]
		if not is_instance_valid(ai) or not is_instance_valid(ai.aircraft):
			continue
		
		# Distance-based update frequency using cached positions (더 공격적인 최적화)
		var update_interval = 8  # Default: every 8 frames
		if has_player:
			# Use cached aircraft index instead of find()
			var aircraft_idx = ai.my_aircraft_index
			if aircraft_idx != -1 and aircraft_idx < _aircraft_positions.size():
				var dist_sq = _aircraft_positions[aircraft_idx].distance_squared_to(player_pos)
				if dist_sq < 250000:  # < 500m: every 2 frames
					update_interval = 2
				elif dist_sq < 1000000:  # < 1000m: every 4 frames
					update_interval = 4
				elif dist_sq < 4000000:  # < 2000m: every 8 frames
					update_interval = 8
				else:  # > 2000m: every 16 frames
					update_interval = 16
		
		if (i + _frame_count) % update_interval != 0:
			continue
		
		ai.process_ai(delta * update_interval)
