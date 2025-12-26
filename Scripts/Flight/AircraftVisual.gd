extends Node3D

class_name AircraftVisual

@export_group("Control Surfaces")
@export var aileron_left: Node3D
@export var aileron_right: Node3D
@export var elevator_left: Node3D
@export var elevator_right: Node3D
@export var rudder: Node3D

@export_group("Animation Settings")
@export var aileron_max_angle: float = 20.0
@export var elevator_max_angle: float = 20.0
@export var rudder_max_angle: float = 15.0
@export var smoothing: float = 10.0

@export_group("Parts Mapping")
@export var fuselage_node: Node3D
@export var left_wing_node: Node3D
@export var right_wing_node: Node3D
@export var horizontal_tail_node: Node3D
@export var vertical_tail_node: Node3D

@export_group("Weapon Points")
@export var gun_muzzles: Array[Node3D] = []
@export var missile_muzzles: Array[Node3D] = []

var _current_aileron: float = 0.0
var _current_elevator: float = 0.0
var _current_rudder: float = 0.0
var _part_nodes: Dictionary = {}

func _ready() -> void:
	_part_nodes = {
		"nose": fuselage_node,
		"fuselage": fuselage_node,
		"engine": fuselage_node,
		"l_wing_in": left_wing_node,
		"l_wing_out": aileron_left,
		"r_wing_in": right_wing_node,
		"r_wing_out": aileron_right,
		"v_tail": vertical_tail_node,
		"h_tail": horizontal_tail_node
	}

func get_part_node(part: String) -> Node3D:
	return _part_nodes.get(part)

func hide_part(part: String) -> void:
	var node = get_part_node(part)
	if node: node.visible = false

func update_animation(input_pitch: float, input_roll: float, input_yaw: float, delta: float) -> void:
	_current_aileron = lerp(_current_aileron, input_roll, smoothing * delta)
	_current_elevator = lerp(_current_elevator, input_pitch, smoothing * delta)
	_current_rudder = lerp(_current_rudder, input_yaw, smoothing * delta)
	
	if aileron_left: aileron_left.rotation_degrees.z = _current_aileron * aileron_max_angle
	if aileron_right: aileron_right.rotation_degrees.z = -_current_aileron * aileron_max_angle
	if elevator_left: elevator_left.rotation_degrees.x = _current_elevator * elevator_max_angle
	if elevator_right: elevator_right.rotation_degrees.x = _current_elevator * elevator_max_angle
	if rudder: rudder.rotation_degrees.y = -_current_rudder * rudder_max_angle
