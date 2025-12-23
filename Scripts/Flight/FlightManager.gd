extends Node

class_name FlightManager

static var instance: FlightManager

var aircrafts: Array[Node] = []
var ai_controllers: Array[Node] = []

# Large-scale systems (NEW)
var mass_aircraft_system: MassAircraftSystem
var mass_ai_system: MassAISystem
var mass_ground_system: MassGroundSystem
var use_mass_system: bool = false # Toggle for testing

# Spatial optimization
var spatial_grid: SpatialGrid

# Thread-Safe Cache
var _aircraft_data_map: Dictionary = {}
var _allies_list: Array[Dictionary] = []
var _enemies_list: Array[Dictionary] = []
var _team_lists_dirty: bool = true # Flag to rebuild team lists only when needed
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

# Thread-safe position cache for AI distance checks
var _aircraft_positions: PackedVector3Array = PackedVector3Array()

func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	# Reserve 1 core for Main Thread/Audio to prevent starvation (WASAPI errors)
	_thread_count = max(1, OS.get_processor_count() - 1)
	
	_query_params = PhysicsRayQueryParameters3D.new()
	_query_params.collide_with_areas = false
	_query_params.collide_with_bodies = true
	# Projectile collision mask: player(1) + ally(2) + enemy(4) + ground(8)
	_query_params.collision_mask = 1 | 2 | 4 | 8
	
	_setup_multimesh()
	
	# Initialize spatial grid
	spatial_grid = SpatialGrid.new()
	spatial_grid.name = "SpatialGrid"
	add_child(spatial_grid)
	
	# Initialize mass systems
	_setup_mass_systems()

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

func _setup_mass_systems() -> void:
	# Create MassAircraftSystem
	mass_aircraft_system = MassAircraftSystem.new()
	mass_aircraft_system.name = "MassAircraftSystem"
	add_child(mass_aircraft_system)
	
	# Create MassAISystem
	mass_ai_system = MassAISystem.new()
	mass_ai_system.name = "MassAISystem"
	add_child(mass_ai_system)
	mass_ai_system.initialize(mass_aircraft_system.MAX_AIRCRAFT)
	
	# Create MassGroundSystem
	mass_ground_system = MassGroundSystem.new()
	mass_ground_system.name = "MassGroundSystem"
	add_child(mass_ground_system)
	
	# Create MassGroundAI
	var ground_ai = MassGroundAI.new()
	ground_ai.name = "MassGroundAI"
	add_child(ground_ai)
	ground_ai.initialize(mass_ground_system.MAX_VEHICLES)
	ground_ai.set_ground_system(mass_ground_system)
	
	print("[FlightManager] Mass systems initialized for 1000+ aircraft and 500+ ground vehicles")

func _exit_tree() -> void:
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
		
	if instance == self:
		instance = null

func register_aircraft(a: Node) -> void:
	if a not in aircrafts:
		aircrafts.append(a)
		_team_lists_dirty = true
	else:
		push_warning("[FlightManager] Aircraft already registered: ", a.get_instance_id())

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
	
	var forward = - tf.basis.z
	p.position = tf.origin
	p.velocity = forward * 200.0
	p.life = 2.0
	p.damage = 10.0
	p.spawn_time = Time.get_ticks_msec() / 1000.0
	
	# Calculate basis for projectile orientation
	# Safety check: Ensure forward is valid
	if forward.is_zero_approx() or not forward.is_normalized():
		forward = - Vector3.FORWARD
	
	var up = Vector3.UP
	var forward_dot = abs(forward.y)
	if forward_dot > 0.99:
		up = Vector3.RIGHT
	p.basis = Basis.looking_at(forward, up).rotated(Vector3.RIGHT, -PI / 2)
	
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
	
	# Process mass system if enabled
	if use_mass_system:
		_process_mass_system(delta)
	
	# Early exit if no legacy aircraft
	var aircraft_count = aircrafts.size()
	if aircraft_count == 0:
		_multi_mesh_instance.multimesh.visible_instance_count = 0
		return
	
	# Update cache every frame (lightweight now)
	_update_cache()
	
	# Start AI processing less frequently (every 3 physics frames for better performance)
	# Start AI processing
	var ai_count = ai_controllers.size()
	if ai_count > 0:
		# Process AI synchronously to prevent data races with spatial grid and cache
		# We process ALL AI controllers to ensure no one is left behind
		# Distance-based skipping is handled inside _process_ai_batch
		_process_ai_batch(0, delta, ai_count, 1)
	
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
	
	# Only do expensive raycasts every 3 frames (better performance)
	var do_raycast = (_frame_count % 3) == 0
	
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
						# Debug: Confirm hit
						if collider.has_method("get") and collider.get("team") != null:
							var team_name = "ALLY" if collider.team == GlobalEnums.Team.ALLY else "ENEMY"
							print("[Projectile] HIT %s aircraft for %.1f damage at %s" % [team_name, p.damage, result.position])
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
	
	# Update spatial grid
	spatial_grid.clear()
	
	# Only update expensive transform cache every 3 frames for non-player aircraft
	var update_all = (_frame_count % 3) == 0
	
	for i in range(aircraft_count):
		var a = aircrafts[i]
		if not is_instance_valid(a):
			_aircraft_positions[i] = Vector3.ZERO
			continue
		
		var id = a.get_instance_id()
		var data = _aircraft_data_map.get(id)
		
		# Always update position for SpatialGrid accuracy
		var current_pos = a.global_position
		_aircraft_positions[i] = current_pos
		spatial_grid.insert(i, current_pos)
		
		# Update other data every 3 frames or if new
		var should_update_data = update_all or a.is_player or not data
		
		if should_update_data:
			if data:
				data.pos = current_pos
				data.transform = a.global_transform
				data.vel = a.velocity
				data.team = a.team
				data.index = i
			else:
				# Create new data
				data = {
					"ref": a,
					"id": id,
					"pos": current_pos,
					"transform": a.global_transform,
					"team": a.team,
					"vel": a.velocity,
					"index": i
				}
				_aircraft_data_map[id] = data
				_team_lists_dirty = true
	
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

func _process_ai_batch(_task_idx: int, delta: float, total_items: int, _total_tasks: int) -> void:
	# Get player position from cached positions (thread-safe)
	var player_pos = Vector3.ZERO
	var has_player = false
	for i in range(_aircraft_positions.size()):
		if i < aircrafts.size() and is_instance_valid(aircrafts[i]) and aircrafts[i].is_player:
			player_pos = _aircraft_positions[i]
			has_player = true
			break
	
	# Process ALL items in this batch (synchronous now)
	for i in range(total_items):
		var ai = ai_controllers[i]
		if not is_instance_valid(ai) or not is_instance_valid(ai.aircraft):
			continue
		
		# Distance-based update frequency using cached positions
		# OPTIMIZED: Reduced frequency to handle 700+ agents
		var update_interval = 16 # Default: every 16 frames (~3.75 FPS)
		if has_player:
			var aircraft_idx = ai.my_aircraft_index
			if aircraft_idx != -1 and aircraft_idx < _aircraft_positions.size():
				var dist_sq = _aircraft_positions[aircraft_idx].distance_squared_to(player_pos)
				if dist_sq < 1000000: # < 1000m: every 4 frames (~15 FPS)
					update_interval = 4
				elif dist_sq < 4000000: # < 2000m: every 8 frames (~7.5 FPS)
					update_interval = 8
		
		if (i + _frame_count) % update_interval != 0:
			continue
		
		ai.process_ai(delta * update_interval)

func _process_mass_system(delta: float) -> void:
	if not mass_aircraft_system or not mass_ai_system:
		return
	
	# Get camera position (from player or main camera)
	var camera_pos = Vector3.ZERO
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		camera_pos = player.global_position
	else:
		var camera = get_viewport().get_camera_3d()
		if camera:
			camera_pos = camera.global_position
	
	# Process AI
	mass_ai_system.process_ai_batch(delta, mass_aircraft_system, camera_pos)
	mass_ai_system.apply_ai_to_mass_system(mass_aircraft_system)
	
	# Mass system physics and rendering handled in its own _physics_process

# Helper functions for spawning mass aircraft
func spawn_mass_aircraft(position: Vector3, team: int, rotation: Vector3 = Vector3.ZERO) -> int:
	if not mass_aircraft_system:
		push_error("[FlightManager] MassAircraftSystem not initialized")
		return -1
	
	return mass_aircraft_system.spawn_aircraft(position, team, rotation)

func destroy_mass_aircraft(index: int) -> void:
	if not mass_aircraft_system:
		return
	
	mass_aircraft_system.destroy_aircraft(index)

func spawn_formation(center: Vector3, team: int, count: int, spacing: float = 50.0, rotation: Vector3 = Vector3.ZERO) -> void:
	# Spawn aircraft in V-formation
	for i in range(count):
		var row = i / 5
		var col = i % 5
		
		var offset = Vector3(
			(col - 2) * spacing,
			row * 2.0, # Slight upward stagger instead of diving down
			- row * spacing
		)
		
		spawn_mass_aircraft(center + offset, team, rotation)
