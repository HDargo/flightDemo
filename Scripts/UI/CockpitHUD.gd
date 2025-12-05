extends Control

class_name CockpitHUD

@onready var cockpit_frame: Control = $CockpitFrame
@onready var speed_display: Label = $Instruments/SpeedDisplay
@onready var altitude_display: Label = $Instruments/AltitudeDisplay
@onready var heading_display: Label = $Instruments/HeadingDisplay
@onready var throttle_bar: ProgressBar = $Instruments/ThrottleBar
@onready var artificial_horizon: Control = $Instruments/ArtificialHorizon
@onready var horizon_container: Control = $Instruments/ArtificialHorizon/HorizonContainer
@onready var horizon_line: ColorRect = $Instruments/ArtificialHorizon/HorizonContainer/HorizonLine
@onready var pitch_ladder: Control = $Instruments/ArtificialHorizon/HorizonContainer/PitchLadder
@onready var sky_rect: ColorRect = $Instruments/ArtificialHorizon/HorizonContainer/Sky
@onready var ground_rect: ColorRect = $Instruments/ArtificialHorizon/HorizonContainer/Ground
@onready var crosshair: Control = $Crosshair
@onready var missile_status: Label = $WeaponStatus/MissileStatus
@onready var lock_indicator: Control = $LockIndicator

var target_aircraft: Aircraft
var is_visible_cockpit: bool = false

func _ready() -> void:
	hide_cockpit()

func show_cockpit() -> void:
	is_visible_cockpit = true
	cockpit_frame.show()
	crosshair.show()
	$Instruments.show()
	$WeaponStatus.show()

func hide_cockpit() -> void:
	is_visible_cockpit = false
	cockpit_frame.hide()
	crosshair.hide()
	$Instruments.hide()
	$WeaponStatus.hide()
	lock_indicator.hide()

func set_aircraft(aircraft: Aircraft) -> void:
	target_aircraft = aircraft

func _process(_delta: float) -> void:
	if not is_instance_valid(target_aircraft) or not is_visible_cockpit:
		return
	
	# Update Speed
	speed_display.text = "%d\nKTS" % int(target_aircraft.current_speed * 1.94384) # m/s to knots
	
	# Update Altitude
	altitude_display.text = "%d\nFT" % int(target_aircraft.global_position.y * 3.28084) # m to feet
	
	# Update Heading (0-360 degrees)
	var forward = -target_aircraft.global_transform.basis.z
	var heading = rad_to_deg(atan2(forward.x, forward.z))
	if heading < 0:
		heading += 360
	heading_display.text = "%03d°" % int(heading)
	
	# Update Throttle Bar
	throttle_bar.value = target_aircraft.throttle * 100
	
	# Update Artificial Horizon
	update_artificial_horizon()
	
	# Update Missile Status
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_fire = current_time - target_aircraft.last_missile_time
	if time_since_fire >= target_aircraft.missile_cooldown:
		missile_status.text = "MISSILE: READY"
		missile_status.modulate = Color.GREEN
	else:
		var remaining = target_aircraft.missile_cooldown - time_since_fire
		missile_status.text = "MISSILE: %.1fs" % remaining
		missile_status.modulate = Color.YELLOW
	
	# Update Lock Indicator
	if is_instance_valid(target_aircraft.locked_target):
		var camera = get_viewport().get_camera_3d()
		if camera and not camera.is_position_behind(target_aircraft.locked_target.global_position):
			var screen_pos = camera.unproject_position(target_aircraft.locked_target.global_position)
			lock_indicator.visible = true
			lock_indicator.position = screen_pos - (lock_indicator.size / 2.0)
		else:
			lock_indicator.visible = false
	else:
		lock_indicator.visible = false

func update_artificial_horizon() -> void:
	# Get aircraft rotation
	var basis = target_aircraft.global_transform.basis
	
	# Calculate pitch (angle from horizontal)
	var forward = -basis.z
	var pitch = rad_to_deg(asin(clamp(forward.y, -1.0, 1.0)))
	
	# Calculate roll (rotation around forward axis)
	var roll = rad_to_deg(atan2(basis.x.y, basis.y.y))
	
	# Rotate the horizon container around its center
	horizon_container.pivot_offset = horizon_container.size / 2.0
	horizon_container.rotation_degrees = roll
	
	# Move horizon elements based on pitch (inverted for correct display)
	var pitch_offset = -pitch * 2.0 # Scale factor for visual effect (negative to invert)
	var center_y = horizon_container.size.y / 2.0
	
	# Position sky and ground
	sky_rect.position.y = -300 + pitch_offset
	ground_rect.position.y = center_y + pitch_offset
	horizon_line.position.y = center_y + pitch_offset
	
	# Update pitch ladder
	update_pitch_ladder(pitch, pitch_offset)

func update_pitch_ladder(pitch: float, _pitch_offset: float) -> void:
	# Clear existing pitch ladder lines
	for child in pitch_ladder.get_children():
		child.queue_free()
	
	# Draw pitch ladder lines every 10 degrees
	var ladder_spacing = 20.0 # pixels per 10 degrees
	var center_y = horizon_container.size.y / 2.0
	
	for i in range(-9, 10): # -90 to +90 degrees
		var angle = i * 10.0
		var y_offset = (pitch - angle) * (ladder_spacing / 10.0)
		
		if abs(y_offset) > horizon_container.size.y / 2.0:
			continue # Don't draw lines outside view
		
		var line = ColorRect.new()
		line.color = Color.WHITE
		line.size = Vector2(60, 2) if i != 0 else Vector2(80, 3)
		line.position = Vector2(horizon_container.size.x / 2.0 - line.size.x / 2.0, center_y + y_offset)
		pitch_ladder.add_child(line)
		
		# Add angle label
		if i != 0:
			var label = Label.new()
			label.text = str(abs(int(angle)))
			label.add_theme_font_size_override("font_size", 12)
			label.position = Vector2(line.position.x - 30, line.position.y - 10)
			pitch_ladder.add_child(label)


