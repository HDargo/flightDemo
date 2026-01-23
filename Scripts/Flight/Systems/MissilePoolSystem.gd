extends Node
class_name MissilePoolSystem

var _missile_pool: Array[Node] = []
var _missile_scene = preload("res://Scenes/Entities/Missile.tscn")

func spawn_missile(tf: Transform3D, target: Node3D, shooter: Node3D, damage: float = 25.0) -> void:
	var m: Missile
	if _missile_pool.is_empty():
		m = _missile_scene.instantiate() as Missile
		get_tree().current_scene.add_child(m)
	else:
		m = _missile_pool.pop_back() as Missile
		if not is_instance_valid(m):
			m = _missile_scene.instantiate() as Missile
			get_tree().current_scene.add_child(m)
	
	m.damage = damage
	m.launch(tf, target, shooter)

func return_missile(m: Missile) -> void:
	if is_instance_valid(m):
		m.hide()
		m.set_physics_process(false)
		m.set_deferred("monitoring", false)
		m.set_deferred("monitorable", false)
		m.global_position = Vector3(0, -1000, 0)
		_missile_pool.append(m)
