extends Node

## Simple test script for mass system
## Add this as autoload or attach to test scene

func _ready() -> void:
	print("=== Mass System Test ===")
	
	# Wait for FlightManager
	await get_tree().process_frame
	
	if not FlightManager.instance:
		push_error("FlightManager not found!")
		return
	
	var fm = FlightManager.instance
	
	# Check if mass systems are initialized
	if not fm.mass_aircraft_system:
		push_error("MassAircraftSystem not initialized!")
		return
	
	print("✓ MassAircraftSystem initialized")
	print("✓ Max capacity: ", fm.mass_aircraft_system.MAX_AIRCRAFT)
	
	# Test spawning
	print("\n--- Testing spawn ---")
	var index1 = fm.spawn_mass_aircraft(Vector3(0, 100, 0), GlobalEnums.Team.ALLY)
	print("Spawned ally at index: ", index1)
	
	var index2 = fm.spawn_mass_aircraft(Vector3(100, 100, 0), GlobalEnums.Team.ENEMY)
	print("Spawned enemy at index: ", index2)
	
	# Check counts
	print("\nActive count: ", fm.mass_aircraft_system.active_count)
	print("Ally count: ", fm.mass_aircraft_system.ally_count)
	print("Enemy count: ", fm.mass_aircraft_system.enemy_count)
	
	# Test formation spawn
	print("\n--- Testing formation spawn ---")
	fm.spawn_formation(Vector3(0, 100, 500), GlobalEnums.Team.ALLY, 10, 50.0)
	
	await get_tree().create_timer(0.1).timeout
	
	print("After formation:")
	print("Active count: ", fm.mass_aircraft_system.active_count)
	print("Ally count: ", fm.mass_aircraft_system.ally_count)
	
	# Test destruction
	print("\n--- Testing destruction ---")
	fm.destroy_mass_aircraft(index1)
	
	await get_tree().create_timer(0.1).timeout
	
	print("After destruction:")
	print("Active count: ", fm.mass_aircraft_system.active_count)
	
	print("\n=== Test Complete ===")

func _process(delta: float) -> void:
	# Performance monitoring
	if Input.is_action_just_pressed("ui_page_down"):
		_print_performance_stats()

func _print_performance_stats() -> void:
	if not FlightManager.instance or not FlightManager.instance.mass_aircraft_system:
		return
	
	var mas = FlightManager.instance.mass_aircraft_system
	
	print("\n=== Performance Stats ===")
	print("Active aircraft: ", mas.active_count)
	print("  Allies: ", mas.ally_count)
	print("  Enemies: ", mas.enemy_count)
	print("FPS: ", Engine.get_frames_per_second())
	print("Compute Shader: ", "Enabled" if mas._use_compute_shader else "CPU Fallback")
	print("========================")
