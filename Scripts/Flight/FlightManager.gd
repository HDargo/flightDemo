extends Node

class_name FlightManager

static var instance: FlightManager

var aircrafts: Array[Node] = []
var ai_controllers: Array[Node] = []

# Thread-Safe Cache
var _aircraft_data_map: Dictionary = {}
var _allies_list: Array[Dictionary] = []
var _enemies_list: Array[Dictionary] = []
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
var buffer_rid: RID
var uniform_set: RID
var _buffer_capacity: int = 1024
var _byte_array: PackedByteArray

# --- Compute Shader (Missile) ---
var missile_shader_rid: RID
var missile_pipeline: RID
var missile_buffer_rid: RID
var missile_uniform_set: RID
var _missile_buffer_capacity: int = 256
var _missile_byte_array: PackedByteArray
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
	
	_resize_buffer(_buffer_capacity)

func _setup_missile_compute() -> void:
	if not rd: return
	
	var shader_file = load("res://Assets/Shaders/Compute/missile_physics.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	missile_shader_rid = rd.shader_create_from_spirv(shader_spirv)
	missile_pipeline = rd.compute_pipeline_create(missile_shader_rid)
	
	_resize_missile_buffer(_missile_buffer_capacity)

func _resize_missile_buffer(new_capacity: int) -> void:
	if missile_uniform_set.is_valid():
		rd.free_rid(missile_uniform_set)
		
	if missile_buffer_rid.is_valid():
		rd.free_rid(missile_buffer_rid)
	
	_missile_buffer_capacity = new_capacity
	# Struct size = 128 bytes (mat4 + 4 vec4s)
	var size = _missile_buffer_capacity * 128
	_missile_byte_array = PackedByteArray()
	_missile_byte_array.resize(size)
	
	missile_buffer_rid = rd.storage_buffer_create(size, _missile_byte_array)
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(missile_buffer_rid)
	
	missile_uniform_set = rd.uniform_set_create([uniform], missile_shader_rid, 0)


func _resize_buffer(new_capacity: int) -> void:
	# Free old uniform set first as it depends on buffer
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
		
	if buffer_rid.is_valid():
		rd.free_rid(buffer_rid)
	
	_buffer_capacity = new_capacity
	# Struct size = 176 bytes (mat4 + 7 vec4s)
	var size = _buffer_capacity * 176
	_byte_array = PackedByteArray()
	_byte_array.resize(size)
	
	buffer_rid = rd.storage_buffer_create(size, _byte_array)
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer_rid)
	
	uniform_set = rd.uniform_set_create([uniform], shader_rid, 0)

func _exit_tree() -> void:
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
	
	if rd:
		# Free dependents first (UniformSets -> Buffers, Pipelines -> Shaders)
		if uniform_set.is_valid(): rd.free_rid(uniform_set)
		if buffer_rid.is_valid(): rd.free_rid(buffer_rid)
		if pipeline.is_valid(): rd.free_rid(pipeline)
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		
		if missile_uniform_set.is_valid(): rd.free_rid(missile_uniform_set)
		if missile_buffer_rid.is_valid(): rd.free_rid(missile_buffer_rid)
		if missile_pipeline.is_valid(): rd.free_rid(missile_pipeline)
		if missile_shader_rid.is_valid(): rd.free_rid(missile_shader_rid)
		
		rd.free()
		rd = null # Prevent double free
		
	if instance == self:
		instance = null

func register_aircraft(a: Node) -> void:
	if not aircrafts.has(a):
		aircrafts.append(a)

func unregister_aircraft(a: Node) -> void:
	if aircrafts.has(a):
		aircrafts.erase(a)
	
	if is_instance_valid(a):
		var id = a.get_instance_id()
		if _aircraft_data_map.has(id):
			_aircraft_data_map.erase(id)

func register_ai(ai: Node) -> void:
	if not ai_controllers.has(ai):
		ai_controllers.append(ai)

func unregister_ai(ai: Node) -> void:
	if ai_controllers.has(ai):
		ai_controllers.erase(ai)

func spawn_projectile(tf: Transform3D) -> void:
	if _projectile_data.size() >= _max_projectiles:
		return
		
	var p: ProjectileData
	if _projectile_pool.is_empty():
		p = ProjectileData.new()
	else:
		p = _projectile_pool.pop_back()
		
	p.position = tf.origin
	p.velocity = -tf.basis.z * 200.0
	p.life = 2.0
	p.damage = 10.0
	p.spawn_time = Time.get_ticks_msec() / 1000.0
	
	if p.velocity.length_squared() > 0.001:
		var up = Vector3.UP
		if abs(up.dot(p.velocity.normalized())) > 0.99:
			up = Vector3.RIGHT
		p.basis = Basis.looking_at(p.velocity, up)
		p.basis = p.basis.rotated(Vector3.RIGHT, -PI/2)
	else:
		p.basis = Basis()
	
	_projectile_data.append(p)
	
	var idx = _projectile_data.size() - 1
	var mm = _multi_mesh_instance.multimesh
	mm.visible_instance_count = _projectile_data.size()
	
	var t = Transform3D(p.basis, p.position)
	mm.set_instance_transform(idx, t)
	mm.set_instance_custom_data(idx, Color(p.velocity.x, p.velocity.y, p.velocity.z, p.spawn_time))

func return_projectile(p: Node) -> void:
	if is_instance_valid(p):
		p.queue_free()

func spawn_missile(tf: Transform3D, target: Node3D, initial_speed: float) -> void:
	var m: Node
	if _missile_pool.is_empty():
		m = _missile_scene.instantiate()
		var root = get_tree().current_scene
		root.add_child(m)
	else:
		m = _missile_pool.pop_back()
		if not is_instance_valid(m):
			m = _missile_scene.instantiate()
			var root = get_tree().current_scene
			root.add_child(m)
	
	if m.has_method("reset"):
		m.reset(tf, target, initial_speed)
	else:
		m.global_transform = tf
		m.target = target
		m.speed = initial_speed
	
	if not active_missiles.has(m):
		active_missiles.append(m)

func return_missile(m: Node) -> void:
	if is_instance_valid(m):
		m.hide()
		m.set_physics_process(false)
		m.global_position = Vector3(0, -1000, 0)
		_missile_pool.append(m)
		if active_missiles.has(m):
			active_missiles.erase(m)

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
	
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
	
	_update_cache()
	
	var ai_count = ai_controllers.size()
	if ai_count > 0:
		var task_count = min(ai_count, _thread_count)
		_ai_task_group_id = WorkerThreadPool.add_group_task(
			_process_ai_batch.bind(delta, ai_count, task_count),
			task_count,
			-1,
			true,
			"AI Logic"
		)
	
	# Compute Shader Physics
	var aircraft_count = aircrafts.size()
	if aircraft_count > 0 and rd:
		if aircraft_count > _buffer_capacity:
			_resize_buffer(aircraft_count + 128)
			
		var buffer_writer = StreamPeerBuffer.new()
		buffer_writer.data_array = _byte_array
		
		for i in range(aircraft_count):
			var a = aircrafts[i]
			if not is_instance_valid(a): continue
			
			var tf = a.global_transform
			var vel = a.velocity
			var speed = a.current_speed
			
			buffer_writer.seek(i * 176)
			buffer_writer.put_float(tf.basis.x.x); buffer_writer.put_float(tf.basis.x.y); buffer_writer.put_float(tf.basis.x.z); buffer_writer.put_float(0.0)
			buffer_writer.put_float(tf.basis.y.x); buffer_writer.put_float(tf.basis.y.y); buffer_writer.put_float(tf.basis.y.z); buffer_writer.put_float(0.0)
			buffer_writer.put_float(tf.basis.z.x); buffer_writer.put_float(tf.basis.z.y); buffer_writer.put_float(tf.basis.z.z); buffer_writer.put_float(0.0)
			buffer_writer.put_float(tf.origin.x); buffer_writer.put_float(tf.origin.y); buffer_writer.put_float(tf.origin.z); buffer_writer.put_float(1.0)
			
			buffer_writer.put_float(vel.x); buffer_writer.put_float(vel.y); buffer_writer.put_float(vel.z); buffer_writer.put_float(speed)
			buffer_writer.put_float(a.current_pitch); buffer_writer.put_float(a.current_roll); buffer_writer.put_float(a.throttle); buffer_writer.put_float(0.0)
			buffer_writer.put_float(a.input_pitch); buffer_writer.put_float(a.input_roll); buffer_writer.put_float(0.0); buffer_writer.put_float(delta)
			buffer_writer.put_float(a.max_speed); buffer_writer.put_float(a.min_speed); buffer_writer.put_float(a.acceleration); buffer_writer.put_float(a.drag_factor)
			buffer_writer.put_float(a.pitch_speed); buffer_writer.put_float(a.roll_speed); buffer_writer.put_float(a.pitch_acceleration); buffer_writer.put_float(a.roll_acceleration)
			buffer_writer.put_float(a._c_engine_factor); buffer_writer.put_float(a._c_lift_factor); buffer_writer.put_float(a._c_h_tail_factor); buffer_writer.put_float(a._c_roll_authority)
			buffer_writer.put_float(a._c_wing_imbalance); buffer_writer.put_float(a._c_v_tail_factor); buffer_writer.put_float(0.0); buffer_writer.put_float(0.0)

		var data = buffer_writer.data_array
		rd.buffer_update(buffer_rid, 0, data.size(), data)
		
		var compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		var groups = ceil(aircraft_count / 64.0)
		rd.compute_list_dispatch(compute_list, int(groups), 1, 1)
		rd.compute_list_end()
		
		rd.submit()
		rd.sync()
		
		var output_bytes = rd.buffer_get_data(buffer_rid)
		var reader = StreamPeerBuffer.new()
		reader.data_array = output_bytes
		
		for i in range(aircraft_count):
			var a = aircrafts[i]
			if not is_instance_valid(a): continue
			
			reader.seek(i * 176)
			
			var bx_x = reader.get_float(); var bx_y = reader.get_float(); var bx_z = reader.get_float(); reader.get_float()
			var by_x = reader.get_float(); var by_y = reader.get_float(); var by_z = reader.get_float(); reader.get_float()
			var bz_x = reader.get_float(); var bz_y = reader.get_float(); var bz_z = reader.get_float(); reader.get_float()
			var ox = reader.get_float(); var oy = reader.get_float(); var oz = reader.get_float(); reader.get_float()
			
			var new_basis = Basis(Vector3(bx_x, bx_y, bx_z), Vector3(by_x, by_y, by_z), Vector3(bz_x, bz_y, bz_z))
			var new_origin = Vector3(ox, oy, oz)
			
			var vx = reader.get_float(); var vy = reader.get_float(); var vz = reader.get_float(); var new_speed = reader.get_float()
			var new_pitch = reader.get_float(); var new_roll = reader.get_float()
			
			if new_basis.x.is_finite() and new_basis.y.is_finite() and new_basis.z.is_finite():
				a.global_basis = new_basis
				a.velocity = Vector3(vx, vy, vz)
				a.current_speed = new_speed
				a.current_pitch = new_pitch
				a.current_roll = new_roll
			else:
				push_warning("Compute shader returned NaN/Inf for aircraft ", a.name)

	# Compute Shader (Missiles)
	var missile_count = active_missiles.size()
	if missile_count > 0 and rd:
		if missile_count > _missile_buffer_capacity:
			_resize_missile_buffer(missile_count + 64)
			
		var buffer_writer = StreamPeerBuffer.new()
		buffer_writer.data_array = _missile_byte_array
		
		for i in range(missile_count):
			var m = active_missiles[i]
			if not is_instance_valid(m): continue
			
			var tf = m.global_transform
			var vel = m.velocity
			var speed = m.speed
			var target_pos = Vector3.ZERO
			var has_target = 0.0
			if is_instance_valid(m.target):
				target_pos = m.target.global_position
				has_target = 1.0
			
			buffer_writer.seek(i * 128)
			# Transform (mat4)
			buffer_writer.put_float(tf.basis.x.x); buffer_writer.put_float(tf.basis.x.y); buffer_writer.put_float(tf.basis.x.z); buffer_writer.put_float(0.0)
			buffer_writer.put_float(tf.basis.y.x); buffer_writer.put_float(tf.basis.y.y); buffer_writer.put_float(tf.basis.y.z); buffer_writer.put_float(0.0)
			buffer_writer.put_float(tf.basis.z.x); buffer_writer.put_float(tf.basis.z.y); buffer_writer.put_float(tf.basis.z.z); buffer_writer.put_float(0.0)
			buffer_writer.put_float(tf.origin.x); buffer_writer.put_float(tf.origin.y); buffer_writer.put_float(tf.origin.z); buffer_writer.put_float(1.0)
			
			# Velocity/Speed (vec4)
			buffer_writer.put_float(vel.x); buffer_writer.put_float(vel.y); buffer_writer.put_float(vel.z); buffer_writer.put_float(speed)
			
			# Target/Life (vec4)
			buffer_writer.put_float(target_pos.x); buffer_writer.put_float(target_pos.y); buffer_writer.put_float(target_pos.z); buffer_writer.put_float(m._current_life)
			
			# Params (vec4)
			buffer_writer.put_float(m.max_speed); buffer_writer.put_float(m.acceleration); buffer_writer.put_float(m.turn_speed); buffer_writer.put_float(m.lifetime)
			
			# State (vec4)
			# x=state (0=Active), y=has_target, z=delta
			buffer_writer.put_float(0.0); buffer_writer.put_float(has_target); buffer_writer.put_float(delta); buffer_writer.put_float(0.0)

		var data = buffer_writer.data_array
		rd.buffer_update(missile_buffer_rid, 0, data.size(), data)
		
		var compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, missile_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, missile_uniform_set, 0)
		var groups = ceil(missile_count / 64.0)
		rd.compute_list_dispatch(compute_list, int(groups), 1, 1)
		rd.compute_list_end()
		
		rd.submit()
		rd.sync()
		
		var output_bytes = rd.buffer_get_data(missile_buffer_rid)
		var reader = StreamPeerBuffer.new()
		reader.data_array = output_bytes
		
		# Iterate backwards to safely remove items
		for i in range(missile_count - 1, -1, -1):
			var m = active_missiles[i]
			if not is_instance_valid(m): continue
			
			reader.seek(i * 128)
			
			var bx_x = reader.get_float(); var bx_y = reader.get_float(); var bx_z = reader.get_float(); reader.get_float()
			var by_x = reader.get_float(); var by_y = reader.get_float(); var by_z = reader.get_float(); reader.get_float()
			var bz_x = reader.get_float(); var bz_y = reader.get_float(); var bz_z = reader.get_float(); reader.get_float()
			var ox = reader.get_float(); var oy = reader.get_float(); var oz = reader.get_float(); reader.get_float()
			
			var vx = reader.get_float(); var vy = reader.get_float(); var vz = reader.get_float(); var new_speed = reader.get_float()
			
			reader.get_float(); reader.get_float(); reader.get_float(); var new_life = reader.get_float()
			reader.get_float(); reader.get_float(); reader.get_float(); reader.get_float()
			var state = reader.get_float()
			
			if state > 0.5:
				# Explode
				m.explode()
			else:
				var new_basis = Basis(Vector3(bx_x, bx_y, bx_z), Vector3(by_x, by_y, by_z), Vector3(bz_x, bz_y, bz_z))
				var new_origin = Vector3(ox, oy, oz)
				
				if new_origin.is_finite() and new_origin.length_squared() < 1e14:
					m.update_from_compute(Transform3D(new_basis, new_origin), Vector3(vx, vy, vz), new_speed, new_life)
				else:
					push_warning("Missile NaN or Out of Bounds")

	# Projectile Movement
	var proj_count = _projectile_data.size()
	if proj_count > 0:
		var current_time = Time.get_ticks_msec() / 1000.0
		_shader_material.set_shader_parameter("current_time", current_time)
		
		var space_state = null
		if aircrafts.size() > 0 and is_instance_valid(aircrafts[0]):
			space_state = aircrafts[0].get_world_3d().direct_space_state
		
		if space_state:
			var query = _query_params
			var mm = _multi_mesh_instance.multimesh
			
			var i = 0
			while i < _projectile_data.size():
				var p = _projectile_data[i]
				p.life -= delta
				var dead = false
				
				if p.life <= 0:
					dead = true
				else:
					var from = p.position
					var to = from + p.velocity * delta
					query.from = from
					query.to = to
					var result = space_state.intersect_ray(query)
					if not result.is_empty():
						if is_instance_valid(result.collider) and result.collider.has_method("take_damage"):
							var hit_pos_local = result.collider.to_local(result.position)
							result.collider.take_damage(p.damage, hit_pos_local)
						dead = true
					else:
						p.position = to
				
				if dead:
					_projectile_pool.append(p)
					var last_idx = _projectile_data.size() - 1
					if i != last_idx:
						_projectile_data[i] = _projectile_data[last_idx]
						var t = mm.get_instance_transform(last_idx)
						var c = mm.get_instance_custom_data(last_idx)
						mm.set_instance_transform(i, t)
						mm.set_instance_custom_data(i, c)
					_projectile_data.pop_back()
				else:
					i += 1
			mm.visible_instance_count = _projectile_data.size()
	else:
		_multi_mesh_instance.multimesh.visible_instance_count = 0

func _update_cache() -> void:
	_allies_list.clear()
	_enemies_list.clear()
	
	for a in aircrafts:
		if is_instance_valid(a):
			var tf = a.global_transform
			a.prepare_for_threads_with_transform(tf)
			
			var id = a.get_instance_id()
			var data: Dictionary
			if _aircraft_data_map.has(id):
				data = _aircraft_data_map[id]
				data["pos"] = tf.origin
				data["transform"] = tf
				data["vel"] = a.velocity
				data["team"] = a.team 
			else:
				data = {
					"ref": a,
					"id": id,
					"pos": tf.origin,
					"transform": tf,
					"team": a.team,
					"vel": a.velocity
				}
				_aircraft_data_map[id] = data
			
			if data.team == GlobalEnums.Team.ALLY:
				_allies_list.append(data)
			elif data.team == GlobalEnums.Team.ENEMY:
				_enemies_list.append(data)

func _process_ai_batch(task_idx: int, delta: float, total_items: int, total_tasks: int) -> void:
	var start_idx = int(float(task_idx) * total_items / total_tasks)
	var end_idx = int(float(task_idx + 1) * total_items / total_tasks)
	
	for i in range(start_idx, end_idx):
		if (i + _frame_count) % 4 != 0:
			continue

		var ai = ai_controllers[i]
		if is_instance_valid(ai):
			ai.process_ai(delta * 4.0)
