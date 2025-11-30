extends Node3D

@onready var particles: GPUParticles3D = $Particles

func _ready() -> void:
	if particles:
		particles.emitting = true
	
	# Auto delete after particles finish
	await get_tree().create_timer(1.0).timeout
	queue_free()
