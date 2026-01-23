extends Node
class_name AircraftWeaponSystem

## Component for handling aircraft weapons (guns and missiles)
## Separates weapon logic from Aircraft main class

@export var missile_lock_range: float = 2000.0
@export var default_weapons: Array[WeaponConfig] = []

# Legacy support properties
var fire_rate: float = 0.1
var missile_cooldown: float = 2.0

# Weapon state
var locked_target: Node3D = null
var active_weapons: Array[WeaponBase] = []

# Properties needed by Aircraft.gd legacy checks
var last_fire_time: float = 0.0
var last_missile_time: float = 0.0

# Internal
var _aircraft: Node3D = null
var _target_search_timer: float = 0.0
var _target_search_interval: float = 0.2  # 5 times per second
var _target_search_task_id: int = -1
var _next_locked_target: Node3D = null

func _ready() -> void:
	_aircraft = get_parent()
	_initialize_weapons()

func _initialize_weapons() -> void:
	# If no weapons defined (legacy), add defaults
	if default_weapons.is_empty():
		_add_legacy_weapons()
	else:
		for config in default_weapons:
			add_weapon(config)

func add_weapon(config: WeaponConfig) -> void:
	if not config: return

	var mounts = _find_mount_points(config.muzzle_name_prefix)
	var weapon: WeaponBase

	if config.type == WeaponConfig.WeaponType.GUN:
		weapon = GunWeapon.new(config, _aircraft, mounts)
	elif config.type == WeaponConfig.WeaponType.MISSILE:
		weapon = MissileWeapon.new(config, _aircraft, mounts)

	if weapon:
		active_weapons.append(weapon)
		add_child(weapon)

func _find_mount_points(prefix: String) -> Array[Node3D]:
	var mounts: Array[Node3D] = []
	if "visual" in _aircraft and is_instance_valid(_aircraft.visual):
		var visual = _aircraft.visual

		# Specific arrays in visual
		if prefix == "gun" and visual.gun_muzzles.size() > 0:
			return visual.gun_muzzles
		elif prefix == "missile" and visual.missile_muzzles.size() > 0:
			return visual.missile_muzzles

		# Generic search
		if visual.has_node(prefix):
			mounts.append(visual.get_node(prefix))
		else:
			# Try finding by pattern in children
			# (Simple fallback)
			pass

	# Fallback if no mounts found (Virtual mounts)
	if mounts.is_empty():
		var dummy = Node3D.new()
		dummy.name = "VirtualMount_" + prefix
		_aircraft.add_child(dummy)
		# Approximate positions based on type
		if prefix.contains("gun"):
			dummy.position = Vector3(0, 0, -2) # Nose
		else:
			dummy.position = Vector3(2, -0.5, 0) # Wing
		mounts.append(dummy)

	return mounts

func _add_legacy_weapons() -> void:
	# Default Gun
	var gun_cfg = WeaponConfig.new()
	gun_cfg.name = "M61 Vulcan"
	gun_cfg.type = WeaponConfig.WeaponType.GUN
	gun_cfg.damage = 10.0
	gun_cfg.fire_rate = fire_rate
	gun_cfg.projectile_speed = 600.0
	gun_cfg.muzzle_name_prefix = "gun"
	add_weapon(gun_cfg)

	# Default Missile
	var msl_cfg = WeaponConfig.new()
	msl_cfg.name = "AIM-9"
	msl_cfg.type = WeaponConfig.WeaponType.MISSILE
	msl_cfg.damage = 30.0
	msl_cfg.fire_rate = missile_cooldown
	msl_cfg.range_val = missile_lock_range
	msl_cfg.muzzle_name_prefix = "missile"
	add_weapon(msl_cfg)

func _exit_tree() -> void:
	# Release lock on target before being destroyed
	if is_instance_valid(locked_target) and locked_target.has_method("set_locked_by_enemy"):
		locked_target.set_locked_by_enemy(false)

func process_weapons(delta: float, input_fire: bool, input_missile: bool) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	for weapon in active_weapons:
		if not is_instance_valid(weapon): continue

		var should_fire = false
		var target = null

		if weapon.config.type == WeaponConfig.WeaponType.GUN:
			should_fire = input_fire
		elif weapon.config.type == WeaponConfig.WeaponType.MISSILE:
			should_fire = input_missile
			target = locked_target
			# Only fire missile if we have a lock? (Optional)
			if not is_instance_valid(target): should_fire = false

		if should_fire and weapon.can_fire(current_time):
			weapon.fire(target)

			# Legacy tracking
			if weapon.config.type == WeaponConfig.WeaponType.GUN:
				last_fire_time = current_time
			else:
				last_missile_time = current_time

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

# Legacy deferred functions removed as they are now handled by Weapon classes
