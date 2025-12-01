extends Area3D

class_name Missile

@export var speed: float = 100.0
@export var max_speed: float = 600.0
@export var acceleration: float = 200.0
@export var turn_speed: float = 3.0
@export var damage: float = 50.0
@export var lifetime: float = 10.0
@export var explosion_radius: float = 10.0

var explosion_scene = preload("res://Scenes/Effects/Explosion.tscn")

var target: Node3D
var velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Initial setup if not pooled
	if velocity == Vector3.ZERO:
		velocity = -transform.basis.z * speed
	
	_start_timer()

func reset(tf: Transform3D, new_target: Node3D, initial_speed: float) -> void:
	global_transform = tf
	target = new_target
	speed = initial_speed
	velocity = -tf.basis.z * speed
	
	# Reset physics state if needed
	set_physics_process(true)
	show()
	
	_start_timer()

func _start_timer() -> void:
	# Cancel previous timer if any (though SceneTreeTimer can't be cancelled easily, we just ignore it or use a variable)
	# Better to use a custom timer logic in _process or a node Timer if we want to cancel.
	# For simplicity, let's use a simple float timer in _process to avoid async issues with pooling.
	_current_life = 0.0

var _current_life: float = 0.0

func _physics_process(delta: float) -> void:
	_current_life += delta
	if _current_life >= lifetime:
		explode()
		return

	# Accelerate
	speed = move_toward(speed, max_speed, acceleration * delta)
	
	# Homing
	if is_instance_valid(target):
		# Rotate towards target
		# Calculate rotation axis and angle
		# Or use look_at with interpolation (simpler)
		var current_quat = transform.basis.get_rotation_quaternion()
		var target_transform = transform.looking_at(target.global_position, Vector3.UP)
		var target_quat = target_transform.basis.get_rotation_quaternion()
		
		# Slerp rotation
		var new_quat = current_quat.slerp(target_quat, turn_speed * delta)
		transform.basis = Basis(new_quat)
	
	# Move with Inertia
	var target_velocity = -transform.basis.z * speed
	# Missiles have high thrust but still some inertia
	velocity = velocity.lerp(target_velocity, 5.0 * delta)
	
	position += velocity * delta

func _on_body_entered(body: Node3D) -> void:
	if body == self: return
	# Don't hit the shooter immediately? (Handled by collision mask usually)
	
	explode()

func explode() -> void:
	# Area damage - Optimized using Physics Query
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = explosion_radius
	query.shape = shape
	query.transform = global_transform
	query.collide_with_bodies = true
	query.collide_with_areas = false
	# query.collision_mask = ... # Set mask if needed
	
	var results = space_state.intersect_shape(query)
	
	for result in results:
		var body = result.collider
		if is_instance_valid(body) and body.has_method("take_damage"):
			var dist = global_position.distance_to(body.global_position)
			# Calculate damage falloff
			var dmg = damage * (1.0 - (dist / explosion_radius))
			body.take_damage(dmg, body.to_local(global_position))
	
	# print("Missile Exploded!")
	
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_parent().add_child(explosion)
		explosion.global_position = global_position
	
	if FlightManager.instance:
		FlightManager.instance.return_missile(self)
	else:
		queue_free()
