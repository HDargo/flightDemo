extends Control

signal aircraft_selected(resource: AircraftResource)

@export var aircrafts: Array[AircraftResource]

@onready var list = $Panel/HBox/LeftPanel/ItemList
@onready var stats_label = $Panel/HBox/LeftPanel/StatsLabel
@onready var preview_anchor = $Panel/HBox/RightPanel/SubViewportContainer/SubViewport/PreviewAnchor
@onready var viewport = $Panel/HBox/RightPanel/SubViewportContainer/SubViewport

var _current_preview_node: Node3D = null

func _ready():
	list.clear()
	for a in aircrafts:
		list.add_item(a.aircraft_name)
	
	if aircrafts.size() > 0:
		list.select(0)
		_on_item_list_item_selected(0)

func _process(delta):
	if _current_preview_node:
		_current_preview_node.rotate_y(delta * 0.5)

func _on_item_list_item_selected(index):
	var a = aircrafts[index]
	
	var stats = "[ %s ]\n\n" % a.aircraft_name
	stats += "Max Speed: %.1f m/s\n" % a.max_speed
	stats += "Acceleration: %.1f\n" % a.acceleration
	stats += "Turn Rate: %.1f\n" % a.turn_speed
	stats += "Fire Rate: %.2f sec\n" % a.fire_rate
	stats_label.text = stats
	
	_update_preview(a)

func _update_preview(data: AircraftResource):
	if _current_preview_node:
		_current_preview_node.queue_free()
		_current_preview_node = null
	
	if data.visual_scene:
		var model = data.visual_scene.instantiate()
		preview_anchor.add_child(model)
		_current_preview_node = model
		
		if model.has_method("set_base_color"):
			model.set_base_color(data.base_color)
		else:
			_apply_color_to_node(model, data.base_color)
		
		model.position = Vector3.ZERO
		model.rotation = Vector3(deg_to_rad(15), deg_to_rad(45), 0)

func _apply_color_to_node(node: Node, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			child.set_surface_override_material(0, mat)
		_apply_color_to_node(child, color)

func _on_select_button_pressed():
	var items = list.get_selected_items()
	if items.size() > 0:
		aircraft_selected.emit(aircrafts[items[0]])
		hide()
