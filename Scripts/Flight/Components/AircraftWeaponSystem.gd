extends Node
class_name AircraftWeaponSystem

## Component for handling aircraft weapons (guns and missiles)
## Separates weapon logic from Aircraft main class

@export var fire_rate: float = 0.1
@export var missile_cooldown: float = 2.0
@export var missile_lock_range: float = 2000.0

# Weapon state
var last_fire_time: float = 0.0
var last_missile_time: float = 0.0
var locked_target: Node3D = null

# Internal
var _aircraft: Node3D = null
var _target_search_timer: float = 0.0
var _target_search_interval: float = 0.2  # 5 times per second
var _target_search_task_id: int = -1
var _next_locked_target: Node3D = null
var _missile_wing_toggle: bool = false

func _ready() -> void:
	_aircraft = get_parent()

func _exit_tree() -> void:
	# Release lock on target before being destroyed
	if is_instance_valid(locked_target) and locked_target.has_method("set_locked_by_enemy"):
		locked_target.set_locked_by_enemy(false)

func process_weapons(delta: float, input_fire: bool, input_missile: bool) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Gun firing
	if input_fire and (current_time - last_fire_time >= fire_rate):
		call_deferred("_deferred_shoot")
	
	# Missile firing
	if input_missile and (current_time - last_missile_time >= missile_cooldown):
		call_deferred("_deferred_fire_missile")

func process_target_search(delta: float) -> void:
	# Check async search result
	if _target_search_task_id != -1:
		if WorkerThreadPool.is_task_completed(_target_search_task_id):
			WorkerThreadPool.wait_for_task_completion(_target_search_task_id)
			_target_search_task_id = -1
			
			# Handle RWR notification
			var new_target = _next_locked_target
			if locked_target != new_target:
				if is_instance_valid(locked_target) and locked_target.has_method("set_locked_by_enemy"):
					locked_target.set_locked_by_enemy(false)
				
				if is_instance_valid(new_target) and new_target.has_method("set_locked_by_enemy"):
					new_target.set_locked_by_enemy(true)
					
			locked_target = new_target
	
	# Throttle target search
	_target_search_timer -= delta
	if _target_search_timer <= 0 and _target_search_task_id == -1:
		_target_search_timer = _target_search_interval
		_start_target_search()

func _start_target_search() -> void:
	if not FlightManager.instance: return
	if not _aircraft: return
	
	# Snapshot data for thread
	var team = _aircraft.team if "team" in _aircraft else GlobalEnums.Team.NEUTRAL
	var enemies = FlightManager.instance.get_enemies_of(team).duplicate()
	var params = {
		"targets": enemies,
		"my_pos": _aircraft.global_position,
		"my_forward": -_aircraft.global_transform.basis.z,
		"range_sq": missile_lock_range * missile_lock_range
	}
	
	_target_search_task_id = WorkerThreadPool.add_task(
		_thread_find_target.bind(params),
		true,
		"Target Search"
	)

func _thread_find_target(params: Dictionary) -> void:
	var best_target = null
	var best_angle = 0.5
	var my_pos = params.my_pos
	var my_forward = params.my_forward
	var range_sq = params.range_sq
	
	for entry in params.targets:
		if not is_instance_valid(entry.ref): continue
		
		var to_target = entry.pos - my_pos
		var dist_sq = to_target.length_squared()
		if dist_sq > range_sq: continue
		
		var dist = sqrt(dist_sq)
		if dist < 0.001: continue
		
		var angle = my_forward.dot(to_target) / dist
		
		if angle > best_angle:
			best_angle = angle
			best_target = entry.ref
	
	_next_locked_target = best_target

func _deferred_shoot() -> void:
	if not _aircraft: return
	
	last_fire_time = Time.get_ticks_msec() / 1000.0
	
	# Try to get muzzle points from visual
	var muzzles = []
	if "visual" in _aircraft and is_instance_valid(_aircraft.visual):
		muzzles = _aircraft.visual.gun_muzzles
	
	if FlightManager.instance:
		if muzzles.size() > 0:
			# Use defined muzzles
			for muzzle in muzzles:
				if is_instance_valid(muzzle):
					FlightManager.instance.spawn_projectile(muzzle.global_transform)
		else:
			# Legacy Fallback: Twin guns
			var offsets = [Vector3(1.5, 0, -1), Vector3(-1.5, 0, -1)]
			for offset in offsets:
				var tf = _aircraft.global_transform * Transform3D(Basis(), offset)
				FlightManager.instance.spawn_projectile(tf)

func _deferred_fire_missile() -> void:
	if not _aircraft: return
	if not locked_target or not is_instance_valid(locked_target):
		return
	
	last_missile_time = Time.get_ticks_msec() / 1000.0
	
	# Try to get missile points from visual
	var muzzles = []
	if "visual" in _aircraft and is_instance_valid(_aircraft.visual):
		muzzles = _aircraft.visual.missile_muzzles
	
	if FlightManager.instance:
		if muzzles.size() > 0:
			# Sequence (toggle) for missiles
			_missile_wing_toggle = not _missile_wing_toggle
			var idx = 0 if _missile_wing_toggle else 1
			if muzzles.size() > idx and is_instance_valid(muzzles[idx]):
				FlightManager.instance.spawn_missile(muzzles[idx].global_transform, locked_target, _aircraft)
			else:
				FlightManager.instance.spawn_missile(muzzles[0].global_transform, locked_target, _aircraft)
		else:
			# Legacy Fallback
			_missile_wing_toggle = not _missile_wing_toggle
			var wing_offset = Vector3(2.0 if _missile_wing_toggle else -2.0, -0.5, 0.0)
			var launch_transform = _aircraft.global_transform * Transform3D(Basis(), wing_offset)
			FlightManager.instance.spawn_missile(launch_transform, locked_target, _aircraft)
