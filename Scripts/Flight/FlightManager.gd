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

var _projectile_data: Array[ProjectileData] = []
var _multi_mesh_instance: MultiMeshInstance3D
var _max_projectiles: int = 10000

func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	# Reserve 1 core for Main Thread/Audio to prevent starvation (WASAPI errors)
	_thread_count = max(1, OS.get_processor_count() - 1)
	
	_query_params = PhysicsRayQueryParameters3D.new()
	_query_params.collide_with_areas = false
	_query_params.collide_with_bodies = true
	
	_setup_multimesh()

func _setup_multimesh() -> void:
	_multi_mesh_instance = MultiMeshInstance3D.new()
	add_child(_multi_mesh_instance)
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.instance_count = _max_projectiles
	mm.visible_instance_count = 0
	
	# Create Mesh (Capsule)
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.5
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.5, 0, 1)
	mat.emission_energy_multiplier = 2.0
	mesh.material = mat
	
	mm.mesh = mesh
	_multi_mesh_instance.multimesh = mm


func _exit_tree() -> void:
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
	if instance == self:
		instance = null

func register_aircraft(a: Node) -> void:
	if not aircrafts.has(a):
		aircrafts.append(a)

func unregister_aircraft(a: Node) -> void:
	if aircrafts.has(a):
		aircrafts.erase(a)

func register_ai(ai: Node) -> void:
	if not ai_controllers.has(ai):
		ai_controllers.append(ai)

func unregister_ai(ai: Node) -> void:
	if ai_controllers.has(ai):
		ai_controllers.erase(ai)

func spawn_projectile(tf: Transform3D) -> void:
	if _projectile_data.size() >= _max_projectiles:
		return # Limit reached
		
	var p = ProjectileData.new()
	p.position = tf.origin
	p.velocity = -tf.basis.z * 200.0 # Default speed 200
	p.life = 2.0 # Default lifetime
	p.damage = 10.0
	
	# Pre-calculate rotation basis
	# Projectiles usually fly straight, so we don't need to look_at every frame
	if p.velocity.length_squared() > 0.001:
		var up = Vector3.UP
		if abs(up.dot(p.velocity.normalized())) > 0.99:
			up = Vector3.RIGHT
		# Create a basis looking at velocity
		p.basis = Basis.looking_at(p.velocity, up)
		# Rotate capsule to lie flat (CapsuleMesh is vertical by default)
		p.basis = p.basis.rotated(Vector3.RIGHT, -PI/2)
	else:
		p.basis = Basis()
	
	_projectile_data.append(p)

func return_projectile(p: Node) -> void:
	# Deprecated: No longer used with MultiMesh system
	if is_instance_valid(p):
		p.queue_free()

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
	
	# 0. Wait for previous Async Tasks
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
	
	# 1. Update Cache (Main Thread - Safe)
	_update_cache()
	
	# 2. AI Logic (Parallel - Async - Batched)
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
	
	# 3. Aircraft Physics Math (Parallel - Sync - Batched)
	var aircraft_count = aircrafts.size()
	if aircraft_count > 0:
		# Optimization: Process only 50% of aircraft physics math per frame
		# This effectively runs physics math at 30 FPS while movement stays at 60+ FPS
		# We use _frame_count to alternate between even and odd indices
		var start_offset = _frame_count % 2
		
		# We need to pass this offset to the batch processor
		# But WorkerThreadPool splits by total items. 
		# Strategy: Filter inside the batch function or create a list of active indices?
		# Filtering inside is cheaper than creating a new array.
		
		var task_count = min(aircraft_count, _thread_count)
		var group_id = WorkerThreadPool.add_group_task(
			_process_physics_batch.bind(delta, aircraft_count, task_count, start_offset),
			task_count,
			-1,
			true,
			"Aircraft Math"
		)
		WorkerThreadPool.wait_for_group_task_completion(group_id)
		
		# 4. Apply Movement (Main Thread - Sequential)
		for a in aircrafts:
			if is_instance_valid(a):
				a.apply_physics_movement(delta)

	# 5. Projectile Movement (MultiMesh - Optimized)
	var proj_count = _projectile_data.size()
	if proj_count > 0:
		var space_state = null
		if aircrafts.size() > 0 and is_instance_valid(aircrafts[0]):
			space_state = aircrafts[0].get_world_3d().direct_space_state
		
		if space_state:
			# Use cached query params
			var query = _query_params
			
			var alive_count = 0
			# Local reference for potential speedup
			var p_data = _projectile_data 
			
			for i in range(proj_count):
				var p = p_data[i]
				
				p.life -= delta
				if p.life <= 0:
					continue # Skip dead (Time out)
				
				var from = p.position
				var to = from + p.velocity * delta
				
				query.from = from
				query.to = to
				
				var result = space_state.intersect_ray(query)
				
				if not result.is_empty():
					# Hit something
					if is_instance_valid(result.collider) and result.collider.has_method("take_damage"):
						# Calculate local hit position
						var hit_pos_local = result.collider.to_local(result.position)
						result.collider.take_damage(p.damage, hit_pos_local)
					
					# Bullet destroyed on impact
					continue 
				else:
					p.position = to
				
				# Keep alive: Move to front if needed
				if alive_count != i:
					p_data[alive_count] = p
				alive_count += 1
			
			# Resize array to remove dead ones at the end
			if alive_count < proj_count:
				p_data.resize(alive_count)
		
		# Update MultiMesh
		var mm = _multi_mesh_instance.multimesh
		mm.visible_instance_count = _projectile_data.size()
		
		for i in range(_projectile_data.size()):
			var p = _projectile_data[i]
			# Use pre-calculated basis + current position (Much faster than looking_at every frame)
			var t = Transform3D(p.basis, p.position)
			mm.set_instance_transform(i, t)
	else:
		_multi_mesh_instance.multimesh.visible_instance_count = 0

func _update_cache() -> void:
	# Do not clear the map, update existing entries to reduce GC
	# _aircraft_data_map.clear() 
	
	# Clear lists but keep map entries
	_allies_list.clear()
	_enemies_list.clear()
	
	for a in aircrafts:
		if is_instance_valid(a):
			# Optimization: Get transform once
			var tf = a.global_transform
			a.prepare_for_threads_with_transform(tf)
			
			var id = a.get_instance_id()
			
			var data: Dictionary
			if _aircraft_data_map.has(id):
				data = _aircraft_data_map[id]
				# Update existing dictionary
				data["pos"] = tf.origin
				data["transform"] = tf
				data["vel"] = a.velocity
				# ref, id, team usually don't change, but let's be safe
				data["team"] = a.team 
			else:
				# Create new dictionary
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
	
	# Cleanup stale entries (Optional: run this less frequently if needed)
	if _frame_count % 60 == 0:
		var current_ids = {} # Use Dictionary for faster lookup than Array.has()
		for a in aircrafts:
			if is_instance_valid(a):
				current_ids[a.get_instance_id()] = true
				
		var keys = _aircraft_data_map.keys()
		for k in keys:
			if not current_ids.has(k):
				_aircraft_data_map.erase(k)

func _process_ai_batch(task_idx: int, delta: float, total_items: int, total_tasks: int) -> void:
	var start_idx = int(float(task_idx) * total_items / total_tasks)
	var end_idx = int(float(task_idx + 1) * total_items / total_tasks)
	
	for i in range(start_idx, end_idx):
		# Optimization: Interleaved updates (Update 1/4 of AIs per frame)
		# 60 FPS -> 15 FPS AI updates. Sufficient for flight logic.
		if (i + _frame_count) % 4 != 0:
			continue

		var ai = ai_controllers[i]
		if is_instance_valid(ai):
			# Pass scaled delta because we are skipping frames
			ai.process_ai(delta * 4.0)

func _process_physics_batch(task_idx: int, delta: float, total_items: int, total_tasks: int, offset: int) -> void:
	var start_idx = int(float(task_idx) * total_items / total_tasks)
	var end_idx = int(float(task_idx + 1) * total_items / total_tasks)
	
	# Double delta because we run every 2 frames
	var sim_delta = delta * 2.0
	
	for i in range(start_idx, end_idx):
		# Interleaved update: Only process if index matches offset (Even/Odd)
		if i % 2 != offset:
			continue
			
		var a = aircrafts[i]
		if is_instance_valid(a):
			a.calculate_forces(sim_delta)
