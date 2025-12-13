extends RigidBody3D
class_name GroundProjectile

@export var damage: float = 25.0
@export var lifetime: float = 10.0
@export var explosion_radius: float = 5.0
@export var explosion_force: float = 10.0

var faction: GlobalEnums.Faction = GlobalEnums.Faction.NEUTRAL
var has_hit: bool = false

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		_explode()

func set_damage(new_damage: float) -> void:
	damage = new_damage

func set_faction(new_faction: GlobalEnums.Faction) -> void:
	faction = new_faction

func set_velocity(velocity: Vector3) -> void:
	linear_velocity = velocity

func _on_body_entered(body: Node) -> void:
	if has_hit:
		return
	
	has_hit = true
	
	if body.has_method("take_damage"):
		var target_faction = GlobalEnums.Faction.NEUTRAL
		if body.has_method("get_faction"):
			target_faction = body.get_faction()
		
		if target_faction != faction and faction != GlobalEnums.Faction.NEUTRAL:
			body.take_damage(damage, global_position, faction)
	
	_explode()

func _explode() -> void:
	if explosion_radius > 0:
		_apply_explosion_damage()
	
	queue_free()

func _apply_explosion_damage() -> void:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 0xFFFFFFFF
	
	var results = space_state.intersect_shape(query, 32)
	
	for result in results:
		var body = result.collider
		if body.has_method("take_damage"):
			var target_faction = GlobalEnums.Faction.NEUTRAL
			if body.has_method("get_faction"):
				target_faction = body.get_faction()
			
			if target_faction != faction and faction != GlobalEnums.Faction.NEUTRAL:
				var distance = global_position.distance_to(body.global_position)
				var damage_multiplier = 1.0 - (distance / explosion_radius)
				var explosion_damage = damage * damage_multiplier * 0.5
				body.take_damage(explosion_damage, global_position, faction)
