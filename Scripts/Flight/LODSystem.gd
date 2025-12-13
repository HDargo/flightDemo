extends Node

class_name LODSystem

## Level-of-Detail system for aircraft rendering
## 3 LOD levels based on distance from camera

enum LODLevel {
	HIGH,    # 0-500m: Full detail
	MEDIUM,  # 500-2000m: Medium detail
	LOW      # 2000m+: Low detail or billboard
}

# LOD distance thresholds (squared for fast comparison)
const LOD_HIGH_DIST_SQ: float = 250000.0    # 500m^2
const LOD_MEDIUM_DIST_SQ: float = 4000000.0 # 2000m^2

# MultiMesh instances per LOD level per team
var _multimesh_ally_high: MultiMeshInstance3D
var _multimesh_ally_medium: MultiMeshInstance3D
var _multimesh_ally_low: MultiMeshInstance3D

var _multimesh_enemy_high: MultiMeshInstance3D
var _multimesh_enemy_medium: MultiMeshInstance3D
var _multimesh_enemy_low: MultiMeshInstance3D

# Meshes per LOD level
var _mesh_high: Mesh
var _mesh_medium: Mesh
var _mesh_low: Mesh

const MAX_PER_LOD: int = 1000

func _ready() -> void:
	_create_lod_meshes()
	_setup_multimeshes()

func _create_lod_meshes() -> void:
	# HIGH LOD: Detailed aircraft
	_mesh_high = _create_aircraft_mesh(3, Color(0.5, 0.5, 0.5))
	
	# MEDIUM LOD: Simplified aircraft
	_mesh_medium = _create_aircraft_mesh(2, Color(0.5, 0.5, 0.5))
	
	# LOW LOD: Simple box or billboard
	_mesh_low = _create_aircraft_mesh(1, Color(0.5, 0.5, 0.5))

func _create_aircraft_mesh(detail_level: int, base_color: Color) -> Mesh:
	# Create aircraft mesh based on detail level
	var arr_mesh = ArrayMesh.new()
	
	match detail_level:
		3:  # HIGH: Capsule body + detailed wings
			var body = CapsuleMesh.new()
			body.radius = 0.3
			body.height = 2.0
			body.radial_segments = 8
			body.rings = 4
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = base_color
			mat.metallic = 0.3
			mat.roughness = 0.7
			body.material = mat
			
			return body
		
		2:  # MEDIUM: Simple capsule
			var body = CapsuleMesh.new()
			body.radius = 0.3
			body.height = 2.0
			body.radial_segments = 4
			body.rings = 2
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = base_color
			body.material = mat
			
			return body
		
		1:  # LOW: Simple box
			var box = BoxMesh.new()
			box.size = Vector3(0.4, 0.4, 1.5)
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = base_color
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			box.material = mat
			
			return box
	
	return CapsuleMesh.new()

func _setup_multimeshes() -> void:
	# Ally LODs
	_multimesh_ally_high = _create_multimesh_instance(_mesh_high, Color(0.2, 0.5, 1.0))
	_multimesh_ally_medium = _create_multimesh_instance(_mesh_medium, Color(0.2, 0.5, 1.0))
	_multimesh_ally_low = _create_multimesh_instance(_mesh_low, Color(0.2, 0.5, 1.0))
	
	add_child(_multimesh_ally_high)
	add_child(_multimesh_ally_medium)
	add_child(_multimesh_ally_low)
	
	# Enemy LODs
	_multimesh_enemy_high = _create_multimesh_instance(_mesh_high, Color(1.0, 0.3, 0.2))
	_multimesh_enemy_medium = _create_multimesh_instance(_mesh_medium, Color(1.0, 0.3, 0.2))
	_multimesh_enemy_low = _create_multimesh_instance(_mesh_low, Color(1.0, 0.3, 0.2))
	
	add_child(_multimesh_enemy_high)
	add_child(_multimesh_enemy_medium)
	add_child(_multimesh_enemy_low)

func _create_multimesh_instance(mesh: Mesh, color: Color) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = MAX_PER_LOD
	mm.visible_instance_count = 0
	
	# Apply color to mesh material
	var colored_mesh = mesh.duplicate()
	var mat = colored_mesh.surface_get_material(0)
	if mat:
		mat = mat.duplicate()
		mat.albedo_color = color
		colored_mesh.surface_set_material(0, mat)
	
	mm.mesh = colored_mesh
	mmi.multimesh = mm
	
	return mmi

func update_lods(camera_pos: Vector3, positions: PackedVector3Array, rotations: PackedVector3Array, teams: PackedInt32Array, states: PackedInt32Array) -> void:
	# Sort aircraft by LOD level
	var ally_high: Array[Transform3D] = []
	var ally_medium: Array[Transform3D] = []
	var ally_low: Array[Transform3D] = []
	
	var enemy_high: Array[Transform3D] = []
	var enemy_medium: Array[Transform3D] = []
	var enemy_low: Array[Transform3D] = []
	
	for i in range(positions.size()):
		if states[i] == 0:
			continue
		
		var pos = positions[i]
		var dist_sq = camera_pos.distance_squared_to(pos)
		
		var basis = Basis.from_euler(rotations[i])
		var transform = Transform3D(basis, pos)
		
		var team = teams[i]
		var lod_level = _get_lod_level(dist_sq)
		
		match lod_level:
			LODLevel.HIGH:
				if team == GlobalEnums.Team.ALLY:
					ally_high.append(transform)
				elif team == GlobalEnums.Team.ENEMY:
					enemy_high.append(transform)
			LODLevel.MEDIUM:
				if team == GlobalEnums.Team.ALLY:
					ally_medium.append(transform)
				elif team == GlobalEnums.Team.ENEMY:
					enemy_medium.append(transform)
			LODLevel.LOW:
				if team == GlobalEnums.Team.ALLY:
					ally_low.append(transform)
				elif team == GlobalEnums.Team.ENEMY:
					enemy_low.append(transform)
	
	# Update MultiMeshes
	_update_multimesh(_multimesh_ally_high, ally_high)
	_update_multimesh(_multimesh_ally_medium, ally_medium)
	_update_multimesh(_multimesh_ally_low, ally_low)
	
	_update_multimesh(_multimesh_enemy_high, enemy_high)
	_update_multimesh(_multimesh_enemy_medium, enemy_medium)
	_update_multimesh(_multimesh_enemy_low, enemy_low)

func _get_lod_level(dist_sq: float) -> LODLevel:
	if dist_sq < LOD_HIGH_DIST_SQ:
		return LODLevel.HIGH
	elif dist_sq < LOD_MEDIUM_DIST_SQ:
		return LODLevel.MEDIUM
	else:
		return LODLevel.LOW

func _update_multimesh(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	var mm = mmi.multimesh
	var count = mini(transforms.size(), MAX_PER_LOD)
	
	for i in range(count):
		mm.set_instance_transform(i, transforms[i])
	
	mm.visible_instance_count = count
