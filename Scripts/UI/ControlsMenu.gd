extends Control

@onready var action_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/ActionList
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/BackButton
@onready var reset_button: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/ResetButton

var action_items: Dictionary = {}
var awaiting_input: String = ""
var awaiting_button: Button = null

# List of flight actions to display
var flight_actions = [
	"flight_pitch_up",
	"flight_pitch_down",
	"flight_roll_left",
	"flight_roll_right",
	"flight_yaw_left",
	"flight_yaw_right",
	"flight_throttle_up",
	"flight_throttle_down",
	"flight_fire_gun",
	"flight_fire_missile"
]

# Friendly names for actions
var action_names = {
	"flight_pitch_up": "Pitch Up",
	"flight_pitch_down": "Pitch Down",
	"flight_roll_left": "Roll Left",
	"flight_roll_right": "Roll Right",
	"flight_yaw_left": "Yaw Left",
	"flight_yaw_right": "Yaw Right",
	"flight_throttle_up": "Throttle Up",
	"flight_throttle_down": "Throttle Down",
	"flight_fire_gun": "Fire Gun",
	"flight_fire_missile": "Fire Missile"
}

func _ready() -> void:
	hide()
	print("ControlsMenu _ready() called")
	print("action_list: ", action_list)
	print("back_button: ", back_button)
	print("reset_button: ", reset_button)
	
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
	if reset_button:
		reset_button.pressed.connect(_on_reset_button_pressed)
	load_controls()
	populate_action_list()

func show_menu() -> void:
	print("ControlsMenu show_menu() called")
	show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("ControlsMenu visible: ", visible)

func hide_menu() -> void:
	hide()
	# Show the pause menu again
	var pause_menu = get_parent()
	if pause_menu and pause_menu.has_method("pause"):
		# Show pause menu containers
		if pause_menu.has_node("CenterContainer"):
			pause_menu.get_node("CenterContainer").show()
		if pause_menu.has_node("ColorRect"):
			pause_menu.get_node("ColorRect").show()

func populate_action_list() -> void:
	# Clear existing items
	for child in action_list.get_children():
		child.queue_free()
	
	action_items.clear()
	
	# Create UI for each action
	for action in flight_actions:
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Action label
		var label = Label.new()
		label.text = action_names.get(action, action)
		label.custom_minimum_size = Vector2(200, 0)
		hbox.add_child(label)
		
		# Get current bindings
		var events = InputMap.action_get_events(action)
		
		# Primary binding button
		var primary_button = Button.new()
		primary_button.custom_minimum_size = Vector2(200, 0)
		primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if events.size() > 0:
			primary_button.text = get_event_text(events[0])
		else:
			primary_button.text = "Not Bound"
		primary_button.pressed.connect(_on_rebind_button_pressed.bind(action, primary_button, 0))
		hbox.add_child(primary_button)
		
		# Secondary binding button
		var secondary_button = Button.new()
		secondary_button.custom_minimum_size = Vector2(200, 0)
		secondary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if events.size() > 1:
			secondary_button.text = get_event_text(events[1])
		else:
			secondary_button.text = "Not Bound"
		secondary_button.pressed.connect(_on_rebind_button_pressed.bind(action, secondary_button, 1))
		hbox.add_child(secondary_button)
		
		action_list.add_child(hbox)
		
		if action not in action_items:
			action_items[action] = []
		action_items[action].append({"button": primary_button, "index": 0})
		action_items[action].append({"button": secondary_button, "index": 1})

func get_event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			_: return "Mouse " + str(event.button_index)
	elif event is InputEventJoypadButton:
		return "Joy Button " + str(event.button_index)
	elif event is InputEventJoypadMotion:
		var axis_name = ""
		match event.axis:
			JOY_AXIS_LEFT_X: axis_name = "Left Stick X"
			JOY_AXIS_LEFT_Y: axis_name = "Left Stick Y"
			JOY_AXIS_RIGHT_X: axis_name = "Right Stick X"
			JOY_AXIS_RIGHT_Y: axis_name = "Right Stick Y"
			JOY_AXIS_TRIGGER_LEFT: axis_name = "Left Trigger"
			JOY_AXIS_TRIGGER_RIGHT: axis_name = "Right Trigger"
			_: axis_name = "Axis " + str(event.axis)
		var direction = "+" if event.axis_value > 0 else "-"
		return axis_name + " " + direction
	return "Unknown"

func _on_rebind_button_pressed(action: String, button: Button, _index: int) -> void:
	if awaiting_input != "":
		return  # Already waiting for input
	
	awaiting_input = action
	awaiting_button = button
	button.text = "Press any key..."

func _input(event: InputEvent) -> void:
	if awaiting_input == "":
		return
	
	# Check for valid input events
	if event is InputEventKey and event.pressed and not event.echo:
		# Ignore ESC (used for pause)
		if event.keycode == KEY_ESCAPE:
			cancel_rebind()
			return
		accept_rebind(event)
	elif event is InputEventMouseButton and event.pressed:
		accept_rebind(event)
	elif event is InputEventJoypadButton and event.pressed:
		accept_rebind(event)
	elif event is InputEventJoypadMotion:
		# Only accept significant axis movements
		if abs(event.axis_value) > 0.5:
			accept_rebind(event)

func accept_rebind(event: InputEvent) -> void:
	if awaiting_input == "" or awaiting_button == null:
		return
	
	var action = awaiting_input
	var events = InputMap.action_get_events(action)
	
	# Find which binding to update
	var binding_index = -1
	for item in action_items[action]:
		if item["button"] == awaiting_button:
			binding_index = item["index"]
			break
	
	if binding_index == -1:
		cancel_rebind()
		return
	
	# Update the binding
	if binding_index < events.size():
		# Replace existing binding
		InputMap.action_erase_event(action, events[binding_index])
	
	InputMap.action_add_event(action, event)
	
	# Update button text
	awaiting_button.text = get_event_text(event)
	
	# Save to config
	save_controls()
	
	cancel_rebind()

func cancel_rebind() -> void:
	if awaiting_button != null:
		# Restore original text
		var action = awaiting_input
		var events = InputMap.action_get_events(action)
		
		var binding_index = -1
		for item in action_items[action]:
			if item["button"] == awaiting_button:
				binding_index = item["index"]
				break
		
		if binding_index < events.size():
			awaiting_button.text = get_event_text(events[binding_index])
		else:
			awaiting_button.text = "Not Bound"
	
	awaiting_input = ""
	awaiting_button = null

func _on_back_button_pressed() -> void:
	hide_menu()

func _on_reset_button_pressed() -> void:
	# Reset to defaults (would need to implement default loading)
	# For now, just reload the scene
	get_tree().reload_current_scene()

func save_controls() -> void:
	var config = ConfigFile.new()
	
	for action in flight_actions:
		var events = InputMap.action_get_events(action)
		var event_data = []
		
		for event in events:
			var data = {}
			if event is InputEventKey:
				data["type"] = "key"
				data["keycode"] = event.physical_keycode
			elif event is InputEventMouseButton:
				data["type"] = "mouse_button"
				data["button_index"] = event.button_index
			elif event is InputEventJoypadButton:
				data["type"] = "joypad_button"
				data["button_index"] = event.button_index
			elif event is InputEventJoypadMotion:
				data["type"] = "joypad_motion"
				data["axis"] = event.axis
				data["axis_value"] = event.axis_value
			
			if not data.is_empty():
				event_data.append(data)
		
		config.set_value("controls", action, event_data)
	
	config.save("user://controls.cfg")

func load_controls() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://controls.cfg")
	
	if err != OK:
		return  # No saved config, use defaults
	
	for action in flight_actions:
		if not config.has_section_key("controls", action):
			continue
		
		var event_data = config.get_value("controls", action)
		
		# Clear current events
		InputMap.action_erase_events(action)
		
		# Add saved events
		for data in event_data:
			var event: InputEvent = null
			
			match data.get("type", ""):
				"key":
					event = InputEventKey.new()
					event.physical_keycode = data["keycode"]
				"mouse_button":
					event = InputEventMouseButton.new()
					event.button_index = data["button_index"]
				"joypad_button":
					event = InputEventJoypadButton.new()
					event.button_index = data["button_index"]
				"joypad_motion":
					event = InputEventJoypadMotion.new()
					event.axis = data["axis"]
					event.axis_value = data["axis_value"]
			
			if event != null:
				InputMap.action_add_event(action, event)
	
	# Refresh UI
	populate_action_list()
