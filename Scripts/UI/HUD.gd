extends Control

class_name HUD

@onready var speed_label: Label = $VBoxContainer/SpeedLabel
@onready var throttle_label: Label = $VBoxContainer/ThrottleLabel
@onready var altitude_label: Label = $VBoxContainer/AltitudeLabel
@onready var missile_label: Label = $VBoxContainer/MissileLabel
@onready var lock_box: Control = $LockBox
@onready var damage_arrow: Polygon2D = $DamageIndicator/Arrow
@onready var chase_hud: Control = $VBoxContainer
@onready var cockpit_hud: Control = $CockpitHUD

var is_cockpit_view: bool = false

# Battle Status
@onready var ally_bar: ColorRect = $BattleStatus/BarBackground/AllyBar
@onready var enemy_bar: ColorRect = $BattleStatus/BarBackground/EnemyBar
@onready var ally_count_label: Label = $BattleStatus/AllyCountLabel
@onready var enemy_count_label: Label = $BattleStatus/EnemyCountLabel
@onready var bar_background: ColorRect = $BattleStatus/BarBackground

var target_aircraft: Aircraft
var _update_timer: float = 0.0

func _ready() -> void:
	if cockpit_hud:
		cockpit_hud.hide_cockpit()

func update_battle_status(allies: int, enemies: int, max_allies: int, max_enemies: int) -> void:
	ally_count_label.text = "Allies: %d" % allies
	enemy_count_label.text = "Enemies: %d" % enemies
	
	var total_width = bar_background.size.x
	var half_width = total_width / 2.0
	
	if max_allies > 0:
		var ally_ratio = float(allies) / float(max_allies)
		ally_bar.size.x = half_width * ally_ratio
	else:
		ally_bar.size.x = 0
		
	if max_enemies > 0:
		var enemy_ratio = float(enemies) / float(max_enemies)
		enemy_bar.size.x = half_width * enemy_ratio
	else:
		enemy_bar.size.x = 0

func _process(delta: float) -> void:
	if not is_instance_valid(target_aircraft):
		lock_box.visible = false
		speed_label.text = "Speed: 0.0"
		throttle_label.text = "Throttle: 0%"
		altitude_label.text = "Alt: 0.0"
		missile_label.text = ""
		return

	# Update Text Labels (Throttled to 10 FPS)
	_update_timer += delta
	if _update_timer >= 0.1:
		_update_timer = 0.0
		speed_label.text = "Speed: %.1f" % target_aircraft.current_speed
		throttle_label.text = "Throttle: %.0f%%" % (target_aircraft.throttle * 100)
		altitude_label.text = "Alt: %.1f" % target_aircraft.global_position.y
		
		# Missile Status
		var current_time = Time.get_ticks_msec() / 1000.0
		var time_since_fire = current_time - target_aircraft.last_missile_time
		if time_since_fire >= target_aircraft.missile_cooldown:
			missile_label.text = "Missile: READY"
			missile_label.modulate = Color.GREEN
		else:
			var remaining = target_aircraft.missile_cooldown - time_since_fire
			missile_label.text = "Missile: %.1fs" % remaining
			missile_label.modulate = Color.RED

	# Target Lock Box (Every Frame for smoothness)
	if is_instance_valid(target_aircraft.locked_target):
		var target = target_aircraft.locked_target
		var camera = get_viewport().get_camera_3d()
		if camera and not camera.is_position_behind(target.global_position):
			var screen_pos = camera.unproject_position(target.global_position)
			lock_box.visible = true
			lock_box.position = screen_pos - (lock_box.size / 2.0)
		else:
			lock_box.visible = false
	else:
		lock_box.visible = false


func set_aircraft(aircraft: Aircraft) -> void:
	target_aircraft = aircraft
	if cockpit_hud:
		cockpit_hud.set_aircraft(aircraft)
	if not target_aircraft.is_connected("damage_taken", _on_damage_taken):
		target_aircraft.connect("damage_taken", _on_damage_taken)

func set_cockpit_view(enabled: bool) -> void:
	is_cockpit_view = enabled
	if enabled:
		chase_hud.hide()
		lock_box.hide()
		if cockpit_hud:
			cockpit_hud.show_cockpit()
	else:
		chase_hud.show()
		lock_box.show()
		if cockpit_hud:
			cockpit_hud.hide_cockpit()

var _game_over_label: Label = null

func show_game_over(message: String) -> void:
	if _game_over_label:
		_game_over_label.text = message
		_game_over_label.visible = true
		return
	
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	
	# Color based on message content
	if "Loading" in message or "loading" in message:
		label.add_theme_color_override("font_color", Color.WHITE)
	elif "DEFEAT" in message:
		label.add_theme_color_override("font_color", Color.RED)
	else:
		label.add_theme_color_override("font_color", Color.GREEN)
	
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over_label = label

func hide_game_over() -> void:
	if _game_over_label:
		_game_over_label.visible = false

func _on_damage_taken(direction: Vector3) -> void:
	# Direction is in local space of the aircraft
	# x is right, z is back
	# We want to point the arrow towards the damage source
	# If damage is from right (+x), arrow should point right
	# Vector2(x, z) angle gives us rotation
	# Godot 2D rotation: 0 is Right, 90 is Down.
	# We want 0 (Up) to be -Z (Forward).
	# Let's map:
	# Damage from Front (-Z): Arrow points Up (0 deg visual, -90 deg math)
	# Damage from Right (+X): Arrow points Right (90 deg visual, 0 deg math)
	# Damage from Back (+Z): Arrow points Down (180 deg visual, 90 deg math)
	# Damage from Left (-X): Arrow points Left (270 deg visual, 180 deg math)
	
	# Vector2(x, z).angle()
	# (1, 0) -> 0 rad (Right)
	# (0, 1) -> PI/2 rad (Down/Back)
	# (-1, 0) -> PI rad (Left)
	# (0, -1) -> -PI/2 rad (Up/Front)
	
	# Our arrow points UP by default (0, -100)
	# So we need to rotate it to match the direction
	# If damage is from Right (1, 0), we want arrow to point Right (Rotation 90 deg)
	# Wait, Vector2(x, z).angle() for (1, 0) is 0.
	# If we use rotation = angle + PI/2:
	# (1, 0) -> 0 + PI/2 = 90 deg (Right). Correct.
	# (0, 1) -> PI/2 + PI/2 = 180 deg (Down). Correct.
	# (-1, 0) -> PI + PI/2 = 270 deg (Left). Correct.
	# (0, -1) -> -PI/2 + PI/2 = 0 deg (Up). Correct.
	
	var angle = Vector2(direction.x, direction.z).angle()
	damage_arrow.rotation = angle + PI/2
	
	damage_arrow.visible = true
	damage_arrow.modulate.a = 1.0
	
	# Fade out
	var tween = create_tween()
	tween.tween_property(damage_arrow, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): damage_arrow.visible = false)
