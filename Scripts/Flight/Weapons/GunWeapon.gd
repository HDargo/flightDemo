extends WeaponBase
class_name GunWeapon

func _fire_implementation(target: Node3D) -> void:
	if not FlightManager.instance: return

	# Guns usually fire from all mount points simultaneously or sequenced?
	# Typically guns are simultaneous if mounted on wings, or sequenced for gatlings.
	# Let's assume simultaneous for now as it's standard for most WW2/Modern jets (unless it's a specific cannon).
	# Actually, WeaponConfig could specify this. For now, let's fire from ALL points.

	var points = get_all_mount_points()
	for tf in points:
		FlightManager.instance.spawn_projectile(tf, config.damage, config.projectile_speed, config.projectile_color)
