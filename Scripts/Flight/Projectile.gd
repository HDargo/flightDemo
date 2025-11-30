extends Area3D

class_name Projectile

@export var speed: float = 200.0
@export var damage: float = 10.0
@export var lifetime: float = 2.0

# Thread-Safe Cache
var _cached_transform: Transform3D
var _new_position: Vector3
var life: float = 0.0

func _ready() -> void:
	set_physics_process(false)
	monitoring = false
	monitorable = false
	
	# Initial setup if not pooled
	reset()
	
	if not FlightManager.instance:
		await get_tree().process_frame
	
	if FlightManager.instance:
		FlightManager.instance.register_projectile(self)

func reset(tf: Transform3D = Transform3D()) -> void:
	life = lifetime
	if tf != Transform3D():
		global_transform = tf
	_new_position = Vector3.ZERO

func _exit_tree() -> void:
	if FlightManager.instance:
		FlightManager.instance.unregister_projectile(self)

func prepare_for_threads() -> void:
	_cached_transform = global_transform

func apply_movement() -> void:
	global_position = _new_position

func on_hit(collider: Node3D, hit_pos: Vector3) -> void:
	if collider.has_method("take_damage"):
		# Calculate local hit position
		var hit_pos_local = collider.to_local(hit_pos)
		collider.take_damage(damage, hit_pos_local)
	
	# Return to pool instead of freeing
	if FlightManager.instance:
		FlightManager.instance.return_projectile(self)
	else:
		queue_free()
