extends WeaponBase
class_name MissileWeapon

func _fire_implementation(target: Node3D) -> void:
	if not FlightManager.instance: return

	# Missiles fire one at a time
	var tf = get_next_mount_point()

	# Pass damage in a struct or extra param?
	# FlightManager.spawn_missile signature needs update
	FlightManager.instance.spawn_missile(tf, target, _aircraft, config.damage)
