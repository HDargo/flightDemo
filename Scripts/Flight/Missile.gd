extends Area3D

class_name Missile

@export var max_speed: float = 600.0
@export var acceleration: float = 200.0
@export var turn_rate: float = 3.0  # Radians per second
@export var damage: float = 50.0
@export var lifetime: float = 10.0
@export var blast_radius: float = 15.0
@export var prox_radius: float = 8.0  # Proximity fuse distance
@export var arm_time: float = 0.5    # Delay before can explode (prevent self-hit)

const START_SPEED: float = 100.0

var explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")

var target: Node3D = null
var shooter: Node3D = null
var _speed: float = START_SPEED
var _life: float = 0.0
var _active: bool = false

# Trail reference
var _trail: GPUParticles3D = null

# Trail template for recreation
var _trail_template: GPUParticles3D = null

func _ready() -> void:
	set_physics_process(false)
	monitoring = false
	monitorable = false
	hide()
	
	# Cache trail reference and create template
	_trail = get_node_or_null("Trail")
	if _trail:
		# Store a template copy for recreation
		_trail_template = _trail.duplicate() as GPUParticles3D
		_trail_template.emitting = false

func launch(spawn_pos: Transform3D, tgt: Node3D, src: Node3D) -> void:
	global_transform = spawn_pos
	target = tgt
	shooter = src
	_speed = START_SPEED
	_life = 0.0
	_active = true
	monitoring = false
	monitorable = false
	show()
	set_physics_process(true)
	
	# Recreate trail if it was reparented
	if not _trail or not is_instance_valid(_trail) or _trail.get_parent() != self:
		if _trail_template:
			_trail = _trail_template.duplicate() as GPUParticles3D
			add_child(_trail)
			_trail.transform = Transform3D(Basis(), Vector3(0, 0, 0.5))
	
	# Restart trail emission
	if _trail:
		_trail.emitting = true

func _physics_process(delta: float) -> void:
	if not _active:
		return
	
	_life += delta
	
	# Lifetime check
	if _life >= lifetime:
		explode()
		return
	
	# Accelerate
	_speed = move_toward(_speed, max_speed, acceleration * delta)
	
	# Turn towards target
	if is_instance_valid(target):
		var to_target = target.global_position - global_position
		var dist_sq = to_target.length_squared()
		
		# Proximity fuse (only after armed)
		if _life >= arm_time and dist_sq < prox_radius * prox_radius:
			explode()
			return
		
		# Rotate towards target
		var forward = -global_transform.basis.z
		var target_dir = to_target.normalized()
		var max_rot = turn_rate * delta
		
		if forward.angle_to(target_dir) < max_rot:
			# Can turn all the way
			forward = target_dir
		else:
			# Slerp towards target
			forward = forward.slerp(target_dir, min(1.0, max_rot / forward.angle_to(target_dir)))
		
		# Update basis to face new direction
		var right = forward.cross(Vector3.UP)
		if right.length_squared() < 0.01:
			right = forward.cross(Vector3.RIGHT)
		right = right.normalized()
		var up = right.cross(forward).normalized()
		global_transform.basis = Basis(right, up, -forward)
	
	# Move forward
	global_position += -global_transform.basis.z * _speed * delta
	
	# Enable collision after arm time
	if _life >= arm_time and not monitoring:
		monitoring = true
		monitorable = true

func _on_body_entered(body: Node3D) -> void:
	if not _active: return
	if body == shooter: return
	if _life < arm_time: return
	
	explode()

func explode() -> void:
	if not _active: return
	_active = false
	set_physics_process(false)
	
	# Detach trail and let it finish independently
	if _trail and is_instance_valid(_trail):
		# Stop emitting NEW particles but keep existing ones
		_trail.emitting = false
		
		# Reparent to scene root so it persists after missile is pooled
		var trail_global_pos = _trail.global_transform
		_trail.reparent(get_tree().current_scene, false)  # false = keep global transform
		_trail.global_transform = trail_global_pos
		
		# Schedule trail cleanup after particles fade
		var cleanup_time = _trail.lifetime + 0.5
		var detached_trail = _trail  # Capture in closure
		get_tree().create_timer(cleanup_time).timeout.connect(func(): 
			if is_instance_valid(detached_trail):
				detached_trail.queue_free()
		)
		
		# Clear reference so we recreate on next launch
		_trail = null
	
	# Blast damage
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = blast_radius
	query.shape = shape
	query.transform = global_transform
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	for r in space_state.intersect_shape(query):
		var b = r.collider
		if b == shooter or not b.has_method("take_damage"):
			continue
		var d = global_position.distance_to(b.global_position)
		var f = 1.0 - clamp(d / blast_radius, 0.0, 1.0)
		
		# Safe to_local conversion
		var local_pos = global_position
		if b is Node3D:
			var det = b.global_transform.basis.determinant()
			if abs(det) > 0.001:
				local_pos = b.to_local(global_position)
			else:
				local_pos = global_position - b.global_position
		b.take_damage(damage * f, local_pos)
	
	# Spawn explosion VFX
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
	
	# Return to pool
	if FlightManager.instance:
		FlightManager.instance.return_missile(self)
	else:
		queue_free()
