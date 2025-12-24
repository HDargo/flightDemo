extends Node
class_name AircraftRegistry

var aircrafts: Array[Node] = []
var spatial_grid: SpatialGrid

# Thread-Safe Cache
var _aircraft_data_map: Dictionary = {}
var _allies_list: Array[Dictionary] = []
var _enemies_list: Array[Dictionary] = []
var _team_lists_dirty: bool = true
var _aircraft_positions: PackedVector3Array = PackedVector3Array()

func _ready() -> void:
	# Initialize spatial grid
	spatial_grid = SpatialGrid.new()
	spatial_grid.name = "SpatialGrid"
	add_child(spatial_grid)

func register_aircraft(a: Node) -> void:
	if a not in aircrafts:
		aircrafts.append(a)
		_team_lists_dirty = true
	else:
		push_warning("[AircraftRegistry] Aircraft already registered: ", a.get_instance_id())

func unregister_aircraft(a: Node) -> void:
	aircrafts.erase(a)
	_team_lists_dirty = true
	
	if is_instance_valid(a):
		var id = a.get_instance_id()
		_aircraft_data_map.erase(id)

func get_aircraft_data(node: Node) -> Dictionary:
	if not is_instance_valid(node): return {}
	var id = node.get_instance_id()
	if _aircraft_data_map.has(id):
		return _aircraft_data_map[id]
	return {}

func get_aircraft_data_by_id(id: int) -> Dictionary:
	if _aircraft_data_map.has(id):
		return _aircraft_data_map[id]
	return {}

func get_enemies_of(team: int) -> Array[Dictionary]:
	if team == GlobalEnums.Team.ALLY:
		return _enemies_list
	elif team == GlobalEnums.Team.ENEMY:
		return _allies_list
	return []

func update_registry(frame_count: int) -> void:
	# Resize position cache to match aircraft count
	var aircraft_count = aircrafts.size()
	if _aircraft_positions.size() != aircraft_count:
		_aircraft_positions.resize(aircraft_count)
		_team_lists_dirty = true
	
	# Update spatial grid
	spatial_grid.clear()
	
	# Only update expensive transform cache every 3 frames for non-player aircraft
	var update_all = (frame_count % 3) == 0
	
	for i in range(aircraft_count):
		var a = aircrafts[i]
		if not is_instance_valid(a):
			_aircraft_positions[i] = Vector3.ZERO
			continue
		
		var id = a.get_instance_id()
		var data = _aircraft_data_map.get(id)
		
		# Always update position for SpatialGrid accuracy
		var current_pos = a.global_position
		_aircraft_positions[i] = current_pos
		spatial_grid.insert(i, current_pos)
		
		# Update other data every 3 frames or if new
		var should_update_data = update_all or a.is_player or not data
		
		if should_update_data:
			if data:
				data.pos = current_pos
				data.transform = a.global_transform
				data.vel = a.velocity
				data.team = a.team
				data.index = i
			else:
				# Create new data
				data = {
					"ref": a,
					"id": id,
					"pos": current_pos,
					"transform": a.global_transform,
					"team": a.team,
					"vel": a.velocity,
					"index": i
				}
				_aircraft_data_map[id] = data
				_team_lists_dirty = true
	
	# Only rebuild team lists when needed (on aircraft add/remove or team change)
	if _team_lists_dirty:
		_allies_list.clear()
		_enemies_list.clear()
		
		for id in _aircraft_data_map:
			var data = _aircraft_data_map[id]
			var team = data.team
			if team == GlobalEnums.Team.ALLY:
				_allies_list.append(data)
			elif team == GlobalEnums.Team.ENEMY:
				_enemies_list.append(data)
		
		_team_lists_dirty = false

func get_aircraft_positions() -> PackedVector3Array:
	return _aircraft_positions
