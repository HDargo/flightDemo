extends Node
class_name AircraftInputHandler

## Component for handling aircraft input (keyboard, mouse, joystick)
## Separates input logic from Aircraft main class

@export var mouse_sensitivity: float = 0.002

# Input state (read by Aircraft)
var input_pitch: float = 0.0
var input_roll: float = 0.0
var input_fire: bool = false
var input_missile: bool = false
var input_throttle_up: bool = false
var input_throttle_down: bool = false

# Internal
var _mouse_input: Vector2 = Vector2.ZERO
var _aircraft: Node3D = null

func _ready() -> void:
	_aircraft = get_parent()
	set_process_unhandled_input(true)

func process_input() -> void:
	# Get input from input actions (supports keyboard, joystick, mouse)
	var pitch_input = Input.get_axis("flight_pitch_up", "flight_pitch_down")
	var roll_input = Input.get_axis("flight_roll_left", "flight_roll_right")
	
	# Apply pitch and roll (inverted for correct feel)
	input_pitch = -pitch_input
	input_roll = -roll_input
	
	# Mouse Input (Accumulated from _unhandled_input)
	if _mouse_input.length_squared() > 0:
		# Add mouse input to keyboard/joystick input
		# Sensitivity is already applied in _unhandled_input
		input_pitch += _mouse_input.y
		input_roll += _mouse_input.x
		
		# Reset accumulator for next frame
		_mouse_input = Vector2.ZERO
	
	# Weapons
	input_fire = Input.is_action_pressed("flight_fire_gun")
	input_missile = Input.is_action_pressed("flight_fire_missile")
	
	# Throttle
	input_throttle_up = Input.is_action_pressed("flight_throttle_up")
	input_throttle_down = Input.is_action_pressed("flight_throttle_down")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Accumulate mouse delta
		# Pitch (Y): Mouse Down -> Pitch Up
		# Roll (X): Mouse Right -> Roll Right
		_mouse_input.y += event.relative.y * mouse_sensitivity
		_mouse_input.x += event.relative.x * mouse_sensitivity
	
	# Camera view toggle
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		var cam = _aircraft.get_node_or_null("CameraRig")
		if cam:
			cam.toggle_view()
	
	# Debug: Test wing damage
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			# Destroy left wing
			print("[DEBUG] Destroying left wing...")
			if _aircraft.has_method("_debug_destroy_left_wing"):
				_aircraft._debug_destroy_left_wing()
		elif event.keycode == KEY_Y:
			# Destroy right wing
			print("[DEBUG] Destroying right wing...")
			if _aircraft.has_method("_debug_destroy_right_wing"):
				_aircraft._debug_destroy_right_wing()
