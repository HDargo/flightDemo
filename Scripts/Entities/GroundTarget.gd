extends StaticBody3D

@export var health: float = 50.0
var _is_flashing: bool = false

func take_damage(amount: float, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	health -= amount
	# print("Target hit! Health: ", health)
	
	if health <= 0:
		die()
		return

	# Flash red (Debounced)
	if not _is_flashing:
		_flash_feedback()

func _flash_feedback() -> void:
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh:
		_is_flashing = true
		# Note: This assumes material is unique or we don't care about sharing
		# Ideally use a ShaderMaterial with a flash parameter
		var mat = mesh.get_active_material(0)
		if mat:
			var original_color = mat.albedo_color
			mat.albedo_color = Color(1, 0.5, 0.5)
			await get_tree().create_timer(0.1).timeout
			if is_instance_valid(mat):
				mat.albedo_color = original_color
		_is_flashing = false

func die() -> void:
	print("Target destroyed!")
	queue_free()
