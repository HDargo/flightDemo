extends Node
class_name MassRenderSystem

# Rendering (LOD support)
var _multimesh_ally_high: MultiMeshInstance3D
var _multimesh_ally_med: MultiMeshInstance3D
var _multimesh_ally_low: MultiMeshInstance3D
var _multimesh_enemy_high: MultiMeshInstance3D
var _multimesh_enemy_med: MultiMeshInstance3D
var _multimesh_enemy_low: MultiMeshInstance3D

# LOD distance thresholds (squared)
const LOD_HIGH_DIST_SQ: float = 250000.0    # 500m
const LOD_MEDIUM_DIST_SQ: float = 4000000.0 # 2000m
const MAX_RENDER_DIST_SQ: float = 100000000.0  # 10km
const FRUSTUM_DOT_THRESHOLD: float = -0.3  # ~120° FOV

var _mass_system: MassAircraftSystem
var _max_instances: int = 0

func initialize(mass_system: MassAircraftSystem, max_instances: int) -> void:
	_mass_system = mass_system
	_max_instances = max_instances
	_setup_multimesh()

func _setup_multimesh() -> void:
	# Ally LODs
	_multimesh_ally_high = _create_lod_multimesh(_create_high_lod_mesh(Color(0.2, 0.5, 1.0)))
	_multimesh_ally_med = _create_lod_multimesh(_create_med_lod_mesh(Color(0.2, 0.5, 1.0)))
	_multimesh_ally_low = _create_lod_multimesh(_create_low_lod_mesh(Color(0.2, 0.5, 1.0)))
	
	add_child(_multimesh_ally_high)
	add_child(_multimesh_ally_med)
	add_child(_multimesh_ally_low)
	
	# Enemy LODs
	_multimesh_enemy_high = _create_lod_multimesh(_create_high_lod_mesh(Color(1.0, 0.3, 0.2)))
	_multimesh_enemy_med = _create_lod_multimesh(_create_med_lod_mesh(Color(1.0, 0.3, 0.2)))
	_multimesh_enemy_low = _create_lod_multimesh(_create_low_lod_mesh(Color(1.0, 0.3, 0.2)))
	
	add_child(_multimesh_enemy_high)
	add_child(_multimesh_enemy_med)
	add_child(_multimesh_enemy_low)

func _create_lod_multimesh(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = _max_instances
	mm.visible_instance_count = 0
	mm.mesh = mesh
	mmi.multimesh = mm
	return mmi

func _create_high_lod_mesh(color: Color) -> Mesh:
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.7
	mesh.material = mat
	
	return mesh

func _create_med_lod_mesh(color: Color) -> Mesh:
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 2.0
	mesh.radial_segments = 4
	mesh.rings = 2
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	
	return mesh

func _create_low_lod_mesh(color: Color) -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.4, 0.4, 1.5)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	
	return mesh

func update_rendering() -> void:
	if not _mass_system:
		return

	# Get camera position and frustum for LOD and culling
	var camera_pos = _get_camera_position()
	var camera = get_viewport().get_camera_3d()
	
	# Frustum culling data
	var camera_forward = Vector3.FORWARD
	if camera:
		camera_forward = -camera.global_transform.basis.z
	
	# LOD arrays
	var ally_high: Array[Transform3D] = []
	var ally_med: Array[Transform3D] = []
	var ally_low: Array[Transform3D] = []
	var enemy_high: Array[Transform3D] = []
	var enemy_med: Array[Transform3D] = []
	var enemy_low: Array[Transform3D] = []
	
	# Access data arrays directly for performance
	var positions = _mass_system.positions
	var rotations = _mass_system.rotations
	var teams = _mass_system.teams
	var states = _mass_system.states
	var max_count = _mass_system.MAX_AIRCRAFT
	
	for i in range(max_count):
		if states[i] == 0:
			continue
		
		var pos = positions[i]
		
		# Distance culling
		var to_aircraft = pos - camera_pos
		var dist_sq = to_aircraft.length_squared()
		
		if dist_sq > MAX_RENDER_DIST_SQ:
			continue  # Too far, cull
		
		# Frustum culling (rough approximation)
		if dist_sq > 1000.0:  # Only cull if not very close
			var dir_normalized = to_aircraft.normalized()
			var dot = dir_normalized.dot(camera_forward)
			
			if dot < FRUSTUM_DOT_THRESHOLD:
				continue  # Behind camera, cull
		
		# Passed culling - determine LOD
		var basis = Basis.from_euler(rotations[i])
		var transform = Transform3D(basis, pos)
		
		var is_ally = teams[i] == GlobalEnums.Team.ALLY
		
		if dist_sq < LOD_HIGH_DIST_SQ:  # < 500m
			if is_ally:
				ally_high.append(transform)
			else:
				enemy_high.append(transform)
		elif dist_sq < LOD_MEDIUM_DIST_SQ:  # 500-2000m
			if is_ally:
				ally_med.append(transform)
			else:
				enemy_med.append(transform)
		else:  # > 2000m
			if is_ally:
				ally_low.append(transform)
			else:
				enemy_low.append(transform)
	
	# Update all LOD MultiMeshes
	_update_lod_multimesh(_multimesh_ally_high, ally_high)
	_update_lod_multimesh(_multimesh_ally_med, ally_med)
	_update_lod_multimesh(_multimesh_ally_low, ally_low)
	_update_lod_multimesh(_multimesh_enemy_high, enemy_high)
	_update_lod_multimesh(_multimesh_enemy_med, enemy_med)
	_update_lod_multimesh(_multimesh_enemy_low, enemy_low)

func _get_camera_position() -> Vector3:
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		return player.global_position
	
	var camera = get_viewport().get_camera_3d()
	if camera:
		return camera.global_position
	
	return Vector3.ZERO

func _update_lod_multimesh(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	var mm = mmi.multimesh
	var count = mini(transforms.size(), _max_instances)
	
	for i in range(count):
		mm.set_instance_transform(i, transforms[i])
	
	mm.visible_instance_count = count

func hide_all() -> void:
	_multimesh_ally_high.multimesh.visible_instance_count = 0
	_multimesh_ally_med.multimesh.visible_instance_count = 0
	_multimesh_ally_low.multimesh.visible_instance_count = 0
	_multimesh_enemy_high.multimesh.visible_instance_count = 0
	_multimesh_enemy_med.multimesh.visible_instance_count = 0
	_multimesh_enemy_low.multimesh.visible_instance_count = 0
