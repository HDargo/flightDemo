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
		
		# Optimization: Use material_override instead of modifying the shared material
		# This prevents cloning the material (memory leak/overhead) and avoids affecting other instances
		var original_override = mesh.material_override
		
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1, 0.3, 0.3)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1, 0, 0)
		flash_mat.emission_energy_multiplier = 2.0
		
		mesh.material_override = flash_mat
		
		await get_tree().create_timer(0.1).timeout
		
		if is_instance_valid(mesh):
			mesh.material_override = original_override
			
		_is_flashing = false

func die() -> void:
	print("Target destroyed!")
	queue_free()
