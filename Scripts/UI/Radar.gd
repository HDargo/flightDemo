extends Control

class_name Radar

@export var radar_range: float = 3000.0
@export var ally_color: Color = Color.CORNFLOWER_BLUE
@export var enemy_color: Color = Color.RED
@export var player_color: Color = Color.GREEN

@onready var radar_display = $RadarDisplay
@onready var player_icon = $RadarDisplay/PlayerIcon

var target_aircraft: Aircraft = null

func _process(_delta: float) -> void:
	if not is_instance_valid(target_aircraft):
		queue_redraw()
		return
	
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(target_aircraft) or not FlightManager.instance or not FlightManager.instance.spatial_grid:
		return
		
	var center = radar_display.position + radar_display.size / 2.0
	var radius = radar_display.size.x / 2.0
	var my_pos = target_aircraft.global_position
	
	# Cache the list locally to avoid repeated getter calls
	var all_aircrafts = FlightManager.instance.cached_aircrafts
	var list_size = all_aircrafts.size()
	
	# Optimization: Only query units within radar range using SpatialGrid
	var nearby_indices = FlightManager.instance.spatial_grid.query_nearby(my_pos, radar_range)
	
	for idx in nearby_indices:
		# Safety Check
		if idx < 0 or idx >= list_size:
			continue
			
		var a = all_aircrafts[idx]
		if not is_instance_valid(a) or a == target_aircraft:
			continue
			
		var offset = a.global_position - my_pos
		var radar_pos = Vector2(offset.x, offset.z) / radar_range * radius
		
		var final_pos = center + radar_pos
		var color = ally_color if a.team == target_aircraft.team else enemy_color
		draw_circle(final_pos, 3.0, color)
		
		if target_aircraft.locked_target == a:
			draw_rect(Rect2(final_pos - Vector2(5, 5), Vector2(10, 10)), color, false, 1.5)

func set_aircraft(a: Aircraft) -> void:
	target_aircraft = a
