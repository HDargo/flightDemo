extends Node
class_name AIThreadScheduler

var ai_controllers: Array[Node] = []
var _ai_task_group_id: int = -1
var _thread_count: int = 1
var _frame_count: int = 0

func _ready() -> void:
	_thread_count = max(1, OS.get_processor_count() - 1)

func register_ai(ai: Node) -> void:
	if ai not in ai_controllers:
		ai_controllers.append(ai)

func unregister_ai(ai: Node) -> void:
	ai_controllers.erase(ai)

func process_ai_batch(delta: float, registry: AircraftRegistry) -> void:
	_frame_count += 1
	var ai_count = ai_controllers.size()
	if ai_count == 0:
		return
		
	# Get player position from cached positions (thread-safe)
	var player_pos = Vector3.ZERO
	var has_player = false
	var positions = registry.get_aircraft_positions()
	var aircrafts = registry.aircrafts
	
	for i in range(positions.size()):
		if i < aircrafts.size() and is_instance_valid(aircrafts[i]) and aircrafts[i].is_player:
			player_pos = positions[i]
			has_player = true
			break
	
	# Process ALL items in this batch (synchronous now)
	# Note: Could be parallelized using WorkerThreadPool if logic is thread-safe
	for i in range(ai_count):
		var ai = ai_controllers[i]
		if not is_instance_valid(ai) or not is_instance_valid(ai.aircraft):
			continue
		
		# Distance-based update frequency using cached positions
		# OPTIMIZED: Reduced frequency to handle 700+ agents
		var update_interval = 16 # Default: every 16 frames (~3.75 FPS)
		if has_player:
			var aircraft_idx = ai.my_aircraft_index
			if aircraft_idx != -1 and aircraft_idx < positions.size():
				var dist_sq = positions[aircraft_idx].distance_squared_to(player_pos)
				if dist_sq < 1000000: # < 1000m: every 4 frames (~15 FPS)
					update_interval = 4
				elif dist_sq < 4000000: # < 2000m: every 8 frames (~7.5 FPS)
					update_interval = 8
		
		if (i + _frame_count) % update_interval != 0:
			continue
		
		ai.process_ai(delta * update_interval)

func _exit_tree() -> void:
	if _ai_task_group_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
		_ai_task_group_id = -1
