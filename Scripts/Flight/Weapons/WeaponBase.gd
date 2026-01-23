extends Node
class_name WeaponBase

# Logic for a single installed weapon

var config: WeaponConfig
var last_fire_time: float = -100.0
var current_ammo: int = -1
var mount_points: Array[Node3D] = []
var _mount_index: int = 0
var _aircraft: Node3D # Owner

func _init(cfg: WeaponConfig, aircraft_ref: Node3D, mounts: Array[Node3D]) -> void:
	config = cfg
	_aircraft = aircraft_ref
	mount_points = mounts
	current_ammo = config.ammo_max

func can_fire(current_time: float) -> bool:
	if current_ammo == 0: return false
	if current_time - last_fire_time < config.fire_rate: return false
	return true

func fire(target: Node3D = null) -> void:
	last_fire_time = Time.get_ticks_msec() / 1000.0
	if current_ammo > 0:
		current_ammo -= 1

	_fire_implementation(target)

func _fire_implementation(target: Node3D) -> void:
	pass # Override

func get_next_mount_point() -> Transform3D:
	if mount_points.is_empty():
		return _aircraft.global_transform

	var pt = mount_points[_mount_index]
	_mount_index = (_mount_index + 1) % mount_points.size()
	return pt.global_transform

func get_all_mount_points() -> Array[Transform3D]:
	var tfs: Array[Transform3D] = []
	for mp in mount_points:
		tfs.append(mp.global_transform)
	return tfs
