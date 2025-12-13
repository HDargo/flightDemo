extends Node

class_name SpatialGrid

## Spatial hash grid for fast proximity queries
## Reduces O(n²) searches to O(1) average case

var grid: Dictionary = {}
var cell_size: float = 500.0  # 500m cells

func clear() -> void:
	grid.clear()

func _get_cell_key(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(pos.x / cell_size),
		int(pos.y / cell_size),
		int(pos.z / cell_size)
	)

func insert(id: int, pos: Vector3) -> void:
	var key = _get_cell_key(pos)
	if not grid.has(key):
		grid[key] = []
	grid[key].append(id)

func query_nearby(pos: Vector3, radius: float = 1000.0) -> Array[int]:
	var results: Array[int] = []
	var center_key = _get_cell_key(pos)
	
	# Calculate how many cells to check based on radius
	var cell_range = int(ceil(radius / cell_size))
	
	# Check cells in range
	for dx in range(-cell_range, cell_range + 1):
		for dy in range(-cell_range, cell_range + 1):
			for dz in range(-cell_range, cell_range + 1):
				var key = center_key + Vector3i(dx, dy, dz)
				if grid.has(key):
					results.append_array(grid[key])
	
	return results

func get_cell_count() -> int:
	return grid.size()

func get_total_objects() -> int:
	var total = 0
	for cell in grid.values():
		total += cell.size()
	return total
