extends Node
class_name ProjectilePoolSystem

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

# Reusable Physics Query
var _query_params: PhysicsRayQueryParameters3D

func _ready() -> void:
	_setup_multimesh()
	_setup_physics_query()

func _setup_physics_query() -> void:
	_query_params = PhysicsRayQueryParameters3D.new()
	_query_params.collide_with_areas = false
	_query_params.collide_with_bodies = true
	# Projectile collision mask: player(1) + ally(2) + enemy(4) + ground(8)
	_query_params.collision_mask = 1 | 2 | 4 | 8

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
	
	_update_multimesh_instance(_projectile_data.size() - 1, p)
	_multi_mesh_instance.multimesh.visible_instance_count = _projectile_data.size()

func update_projectiles(delta: float, space_state: PhysicsDirectSpaceState3D, frame_count: int) -> void:
	var proj_count = _projectile_data.size()
	if proj_count == 0:
		_multi_mesh_instance.multimesh.visible_instance_count = 0
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	_shader_material.set_shader_parameter("current_time", current_time)
	
	if not space_state:
		return
	
	var query = _query_params
	var mm = _multi_mesh_instance.multimesh
	var i = 0
	
	# Only do expensive raycasts every 3 frames (better performance)
	var do_raycast = (frame_count % 3) == 0
	
	while i < _projectile_data.size():
		var p = _projectile_data[i]
		p.life -= delta
		
		if p.life <= 0:
			_recycle_projectile(i)
		else:
			var movement = p.velocity * delta
			
			# Ray cast (skip every other frame for performance)
			if do_raycast:
				query.from = p.position
				query.to = p.position + movement
				var result = space_state.intersect_ray(query)
				
				if not result.is_empty():
					_handle_collision(result, p)
					_recycle_projectile(i)
					continue
			
			# Still alive - update position
			p.position += movement
			i += 1
	
	mm.visible_instance_count = _projectile_data.size()

func _recycle_projectile(index: int) -> void:
	var p = _projectile_data[index]
	_projectile_pool.append(p)
	
	var last_idx = _projectile_data.size() - 1
	if index != last_idx:
		var last_p = _projectile_data[last_idx]
		_projectile_data[index] = last_p
		# Update multimesh for the swapped item
		_update_multimesh_instance(index, last_p)
		
	_projectile_data.pop_back()

func _update_multimesh_instance(index: int, p: ProjectileData) -> void:
	var mm = _multi_mesh_instance.multimesh
	mm.set_instance_transform(index, Transform3D(p.basis, p.position))
	mm.set_instance_custom_data(index, Color(p.velocity.x, p.velocity.y, p.velocity.z, p.spawn_time))

func _handle_collision(result: Dictionary, p: ProjectileData) -> void:
	# Hit something
	var collider = result.collider
	if is_instance_valid(collider) and collider.has_method("take_damage"):
		collider.take_damage(p.damage, collider.to_local(result.position))
		# Debug: Confirm hit
		if collider.has_method("get") and collider.get("team") != null:
			var team_name = "ALLY" if collider.team == GlobalEnums.Team.ALLY else "ENEMY"
			# print("[Projectile] HIT %s aircraft for %.1f damage" % [team_name, p.damage])

func return_projectile(p: Node) -> void:
	if is_instance_valid(p):
		p.queue_free()
