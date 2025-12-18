# 모듈화 기회 상세 분석 (Detailed Modularization Opportunities)

**날짜**: 2025-12-18  
**목적**: 코드 검토 후 구체적인 모듈화 대상 식별

---

## 🔍 FlightManager.gd 상세 분석

### 현재 구조 (510 lines)

```gdscript
FlightManager.gd
├─ Lines 1-75:    초기화 및 설정
├─ Lines 76-127:  Mass 시스템 설정
├─ Lines 136-156: Aircraft 등록 관리
├─ Lines 158-218: Missile Pool 시스템
├─ Lines 160-196: Projectile Pool 시스템
├─ Lines 220-237: 데이터 조회 메서드
├─ Lines 239-343: _physics_process (메인 루프)
├─ Lines 345-414: _update_cache (캐싱 시스템)
└─ Lines 416-511: _process_ai_batch (AI 스레딩)
```

### 모듈화 대상 상세

#### 1. Projectile Pool System (Lines 160-196, 279-343)

**현재 코드 구조**:
```gdscript
class ProjectileData:
    var position: Vector3
    var velocity: Vector3
    var life: float
    var damage: float = 10.0
    var basis: Basis
    var spawn_time: float

var _projectile_data: Array[ProjectileData] = []
var _projectile_pool: Array[ProjectileData] = []
var _multi_mesh_instance: MultiMeshInstance3D
var _max_projectiles: int = 10000
var _shader_material: ShaderMaterial

func _setup_multimesh() -> void:
    # 76 lines of setup code

func spawn_projectile(tf: Transform3D) -> void:
    # 28 lines of spawn logic

# In _physics_process:
func update_projectiles(delta: float):
    # 64 lines of update logic
    # - Raycast
    # - Movement
    # - Collision detection
    # - Recycling
```

**제안 모듈**:
```gdscript
// Scripts/Flight/Systems/ProjectilePoolSystem.gd
class_name ProjectilePoolSystem
extends Node

# Public API
func spawn_projectile(tf: Transform3D) -> void
func update_projectiles(delta: float, space_state: PhysicsDirectSpaceState3D) -> void
func get_projectile_count() -> int
func clear_all() -> void

# Internal
func _setup_multimesh() -> void
func _process_raycast(p: ProjectileData, delta: float) -> bool
func _recycle_projectile(idx: int) -> void
```

**분리 이점**:
- ✅ 독립 테스트 가능 (다양한 시나리오)
- ✅ 다른 프로젝트에 이식 가능
- ✅ 성능 프로파일링 쉬움
- ✅ MultiMesh 관련 코드 격리

---

#### 2. Missile Pool System (Lines 198-218)

**현재 코드**:
```gdscript
var _missile_pool: Array[Node] = []
var _missile_scene = preload("res://Scenes/Entities/Missile.tscn")

func spawn_missile(tf: Transform3D, target: Node3D, shooter: Node3D) -> void:
    var m: Missile
    if _missile_pool.is_empty():
        m = _missile_scene.instantiate() as Missile
        get_tree().current_scene.add_child(m)
    else:
        m = _missile_pool.pop_back() as Missile
        if not is_instance_valid(m):
            m = _missile_scene.instantiate() as Missile
            get_tree().current_scene.add_child(m)
    
    m.launch(tf, target, shooter)

func return_missile(m: Missile) -> void:
    if is_instance_valid(m):
        m.hide()
        m.set_physics_process(false)
        m.set_deferred("monitoring", false)
        m.set_deferred("monitorable", false)
        m.global_position = Vector3(0, -1000, 0)
        _missile_pool.append(m)
```

**제안 모듈**:
```gdscript
// Scripts/Flight/Systems/MissilePoolSystem.gd
class_name MissilePoolSystem
extends Node

@export var missile_scene: PackedScene
@export var max_pool_size: int = 100
@export var prewarm_count: int = 10

# Public API
func spawn_missile(tf: Transform3D, target: Node3D, shooter: Node3D) -> Missile
func return_missile(m: Missile) -> void
func clear_pool() -> void
func get_active_count() -> int
func get_pooled_count() -> int

# Internal
func _prewarm_pool() -> void
func _create_missile() -> Missile
func _reset_missile(m: Missile) -> void
```

**분리 이점**:
- ✅ Pool 크기 관리 독립
- ✅ Prewarm 기능 추가 용이
- ✅ 다른 무기 타입 추가 시 재사용
- ✅ 메모리 사용량 추적 쉬움

---

#### 3. Aircraft Registry (Lines 136-156, 220-237, 345-414)

**현재 코드**:
```gdscript
var aircrafts: Array[Node] = []
var spatial_grid: SpatialGrid
var _aircraft_data_map: Dictionary = {}
var _allies_list: Array[Dictionary] = []
var _enemies_list: Array[Dictionary] = []
var _team_lists_dirty: bool = true
var _aircraft_positions: PackedVector3Array = PackedVector3Array()

func register_aircraft(a: Node) -> void:
    if a not in aircrafts:
        aircrafts.append(a)
        _team_lists_dirty = true

func unregister_aircraft(a: Node) -> void:
    aircrafts.erase(a)
    _team_lists_dirty = true
    if is_instance_valid(a):
        var id = a.get_instance_id()
        _aircraft_data_map.erase(id)

func get_aircraft_data(node: Node) -> Dictionary: # ...
func get_aircraft_data_by_id(id: int) -> Dictionary: # ...
func get_enemies_of(team: int) -> Array[Dictionary]: # ...

func _update_cache() -> void:
    # 69 lines of cache update logic
    # - Position caching
    # - Spatial grid update
    # - Transform caching
    # - Team list rebuilding
```

**제안 모듈**:
```gdscript
// Scripts/Flight/Systems/AircraftRegistry.gd
class_name AircraftRegistry
extends Node

# Public API
func register_aircraft(a: Node) -> void
func unregister_aircraft(a: Node) -> void
func get_aircraft_data(node: Node) -> Dictionary
func get_aircraft_data_by_id(id: int) -> Dictionary
func get_all_aircraft() -> Array[Node]
func get_allies() -> Array[Dictionary]
func get_enemies() -> Array[Dictionary]
func get_enemies_of(team: int) -> Array[Dictionary]
func get_aircraft_count() -> int
func update_cache(frame_count: int) -> void

# Spatial queries
func query_nearby(pos: Vector3, radius: float) -> Array[Dictionary]
func query_in_frustum(frustum: Array[Plane]) -> Array[Dictionary]

# Internal
var aircrafts: Array[Node] = []
var spatial_grid: SpatialGrid
var _aircraft_data_map: Dictionary = {}
var _allies_list: Array[Dictionary] = []
var _enemies_list: Array[Dictionary] = []
var _team_lists_dirty: bool = true
var _aircraft_positions: PackedVector3Array = PackedVector3Array()

func _rebuild_team_lists() -> void
func _update_spatial_grid() -> void
func _update_aircraft_data(idx: int, aircraft: Node) -> void
```

**분리 이점**:
- ✅ 엔티티 관리 로직 중앙화
- ✅ 공간 쿼리 최적화 독립
- ✅ 다른 엔티티 타입으로 확장 가능
- ✅ 캐싱 전략 변경 용이

---

#### 4. AI Thread Scheduler (Lines 158, 239-276, 416-462)

**현재 코드**:
```gdscript
var ai_controllers: Array[Node] = []
var _ai_task_group_id: int = -1
var _thread_count: int = 1
var _frame_count: int = 0

func register_ai(ai: Node) -> void:
    if ai not in ai_controllers:
        ai_controllers.append(ai)

func unregister_ai(ai: Node) -> void:
    ai_controllers.erase(ai)

# In _physics_process:
var ai_count = ai_controllers.size()
if ai_count > 0 and (_frame_count % 3) == 0:
    if _ai_task_group_id != -1:
        WorkerThreadPool.wait_for_group_task_completion(_ai_task_group_id)
        _ai_task_group_id = -1
    
    var max_ai_per_frame = min(ai_count, max(5, aircraft_count / 2))
    var ai_to_process = min(ai_count, max_ai_per_frame)
    var task_count = min(ai_to_process, _thread_count)
    
    _ai_task_group_id = WorkerThreadPool.add_group_task(
        _process_ai_batch.bind(delta * 3.0, ai_to_process, task_count),
        task_count, -1, true, "AI Logic"
    )

func _process_ai_batch(task_idx: int, delta: float, total_items: int, total_tasks: int) -> void:
    # 46 lines of batch processing logic
    # - Distance-based update intervals
    # - Player position caching
    # - AI update throttling
```

**제안 모듈**:
```gdscript
// Scripts/Flight/Systems/AIThreadScheduler.gd
class_name AIThreadScheduler
extends Node

@export var update_interval: int = 3  # Process AI every N frames
@export var max_ai_per_frame: int = 100
@export var enable_distance_lod: bool = true

# Public API
func register_ai(ai: Node) -> void
func unregister_ai(ai: Node) -> void
func process_ai_batch(delta: float, registry: AircraftRegistry) -> void
func wait_for_completion() -> void
func get_active_ai_count() -> int
func get_thread_count() -> int

# Internal
var ai_controllers: Array[Node] = []
var _ai_task_group_id: int = -1
var _thread_count: int = 1

func _calculate_update_interval(ai: Node, player_pos: Vector3) -> int
func _process_ai_batch(task_idx: int, delta: float, total_items: int, total_tasks: int) -> void
```

**분리 이점**:
- ✅ 스레딩 로직 격리
- ✅ LOD 업데이트 전략 독립 조정
- ✅ 다른 AI 시스템 (Ground, Naval)에 재사용
- ✅ 성능 튜닝 용이

---

## 🔍 MassAircraftSystem.gd 상세 분석

### 현재 구조 (612 lines)

```gdscript
MassAircraftSystem.gd
├─ Lines 1-100:   데이터 구조 및 초기화
├─ Lines 101-165: MultiMesh 설정 (LOD별 6개)
├─ Lines 166-235: Compute Shader 초기화
├─ Lines 236-285: Spawn/Destroy 로직
├─ Lines 286-498: _physics_process (메인 물리)
│  ├─ CPU Physics (300+ lines)
│  └─ GPU Compute dispatch
├─ Lines 499-612: 렌더링 업데이트 (LOD, Culling)
```

### 모듈화 대상 상세

#### 1. Mass Physics Calculator (Lines 286-498)

**현재 코드**:
```gdscript
func _physics_process(delta: float) -> void:
    if _use_compute_shader and _rd:
        # GPU path (30 lines)
        _dispatch_compute_shader(delta)
    else:
        # CPU fallback (300+ lines)
        for i in range(active_count):
            if states[i] != 1: continue
            
            # Throttle & Speed (20 lines)
            var target_speed = lerp(min_speed, max_speed, throttles[i]) * engine_factors[i]
            speeds[i] = move_toward(speeds[i], target_speed, acceleration * engine_factors[i] * delta)
            # ...
            
            # Rotation (30 lines)
            var pitch_input = input_pitches[i]
            var roll_input = input_rolls[i]
            # ...
            
            # Lift & Drag (40 lines)
            var forward = -basis.z
            var up = basis.y
            var lift_magnitude = lift_factor * lift_factors[i] * speeds[i] * speeds[i]
            # ...
            
            # Collision Avoidance (50 lines)
            # Ground check
            # Aircraft proximity check
            # ...
    
    # Update transforms (40 lines)
    _update_multimesh_transforms(camera_pos)
```

**제안 모듈**:
```gdscript
// Scripts/Flight/Systems/MassPhysicsCalculator.gd
class_name MassPhysicsCalculator
extends Node

# Configuration
@export var use_gpu: bool = false
@export var enable_collision_avoidance: bool = true

# Public API
func calculate_physics(
    data: MassPhysicsData,
    delta: float
) -> void

func initialize_gpu(max_entities: int) -> bool
func cleanup_gpu() -> void

# CPU Physics
func _calculate_cpu_physics(data: MassPhysicsData, delta: float) -> void:
    func _update_throttle_and_speed(idx: int, delta: float) -> void
    func _update_rotation(idx: int, delta: float) -> void
    func _calculate_lift_and_drag(idx: int, delta: float) -> void
    func _check_collision_avoidance(idx: int, delta: float) -> void

# GPU Physics
func _calculate_gpu_physics(data: MassPhysicsData, delta: float) -> void:
    func _dispatch_compute_shader(delta: float) -> void
    func _readback_results() -> void

# Data structure
class MassPhysicsData:
    var positions: PackedVector3Array
    var velocities: PackedVector3Array
    var rotations: PackedVector3Array
    var speeds: PackedFloat32Array
    var throttles: PackedFloat32Array
    var engine_factors: PackedFloat32Array
    var lift_factors: PackedFloat32Array
    var input_pitches: PackedFloat32Array
    var input_rolls: PackedFloat32Array
    var input_yaws: PackedFloat32Array
    var states: PackedInt32Array
    var active_count: int
```

**분리 이점**:
- ✅ 물리 로직 독립 테스트
- ✅ CPU/GPU 구현 비교 용이
- ✅ Ground/Naval 시스템에 재사용
- ✅ 물리 파라미터 튜닝 명확

---

#### 2. Mass Render System (Lines 101-165, 499-612)

**현재 코드**:
```gdscript
func _setup_multimesh() -> void:
    # Ally LOD levels
    _multimesh_ally_high = MultiMeshInstance3D.new()
    _multimesh_ally_med = MultiMeshInstance3D.new()
    _multimesh_ally_low = MultiMeshInstance3D.new()
    # Enemy LOD levels
    _multimesh_enemy_high = MultiMeshInstance3D.new()
    _multimesh_enemy_med = MultiMeshInstance3D.new()
    _multimesh_enemy_low = MultiMeshInstance3D.new()
    # Setup each... (64 lines)

func _update_multimesh_transforms(camera_pos: Vector3) -> void:
    # LOD calculation (20 lines)
    var ally_high_count = 0
    var ally_med_count = 0
    var ally_low_count = 0
    # ...
    
    # Frustum culling (30 lines)
    var frustum_planes = _get_frustum_planes()
    # ...
    
    # Transform update (60 lines)
    for i in range(active_count):
        var dist_sq = positions[i].distance_squared_to(camera_pos)
        var lod_level = _calculate_lod_level(dist_sq)
        var is_in_frustum = _check_frustum(positions[i], frustum_planes)
        # ...
```

**제안 모듈**:
```gdscript
// Scripts/Flight/Systems/MassRenderSystem.gd
class_name MassRenderSystem
extends Node

# Configuration
@export var enable_lod: bool = true
@export var enable_frustum_culling: bool = true
@export var lod_high_distance: float = 500.0
@export var lod_medium_distance: float = 2000.0

# Public API
func initialize(max_entities: int, mesh: Mesh) -> void
func update_transforms(
    data: MassRenderData,
    camera_pos: Vector3,
    camera_frustum: Array[Plane]
) -> void
func set_visible(visible: bool) -> void

# LOD Management
enum LODLevel { HIGH, MEDIUM, LOW }

class LODGroup:
    var multimesh: MultiMeshInstance3D
    var instance_count: int = 0
    var transforms: Array[Transform3D] = []

var _ally_lods: Dictionary = {}  # LODLevel -> LODGroup
var _enemy_lods: Dictionary = {}  # LODLevel -> LODGroup

# Internal
func _setup_multimesh(team: int, lod: LODLevel, mesh: Mesh) -> MultiMeshInstance3D
func _calculate_lod_level(dist_sq: float) -> LODLevel
func _check_frustum(pos: Vector3, planes: Array[Plane]) -> bool
func _update_lod_group(group: LODGroup, transforms: Array[Transform3D]) -> void

# Data structure
class MassRenderData:
    var positions: PackedVector3Array
    var rotations: PackedVector3Array
    var teams: PackedInt32Array
    var states: PackedInt32Array
    var active_count: int
```

**분리 이점**:
- ✅ 렌더링 로직 격리
- ✅ LOD 전략 독립 조정
- ✅ Occlusion culling 추가 용이
- ✅ 다른 Mass 시스템에 재사용

---

## 🎯 UI 컴포넌트 모듈화 기회

### ControlsMenu.gd (306 lines)

**분석**:
```gdscript
Lines 1-70:    초기화 및 메뉴 표시
Lines 71-150:  UI 생성 (populate_action_list)
Lines 151-220: 키 바인딩 로직 (_on_rebind_button_pressed)
Lines 221-260: 설정 저장/로드
Lines 261-306: 입력 이벤트 처리 및 충돌 감지
```

**제안**:
```gdscript
// Scripts/UI/Components/InputRebindHandler.gd
class_name InputRebindHandler
extends Node

func create_action_ui(action: String) -> Control
func handle_rebind(action: String, button: Button, slot: int) -> void
func detect_input_conflict(event: InputEvent, action: String) -> String

// Scripts/UI/Components/InputConfigManager.gd
class_name InputConfigManager
extends Node

func save_controls() -> void
func load_controls() -> void
func reset_to_defaults() -> void
func get_config_path() -> String
```

---

### HUD.gd (225 lines)

**분석**:
```gdscript
Lines 1-55:    초기화 및 노드 참조
Lines 56-74:   전투 상태 표시 (update_battle_status)
Lines 75-120:  프레임 업데이트 (_process)
Lines 121-150: 물리 업데이트 (on_physics_updated)
Lines 151-180: 데미지 표시 (on_damage_taken)
Lines 181-225: 카메라 뷰 전환 및 경고
```

**제안**:
```gdscript
// Scripts/UI/Components/BattleStatusDisplay.gd
class_name BattleStatusDisplay
extends Control

func update_status(allies: int, enemies: int, max_allies: int, max_enemies: int) -> void
func set_visible(visible: bool) -> void

// Scripts/UI/Components/FlightInstruments.gd
class_name FlightInstruments
extends Control

func update_speed(speed: float) -> void
func update_altitude(altitude: float, vertical_speed: float) -> void
func update_throttle(throttle: float) -> void
func update_aoa(aoa: float, stall_factor: float) -> void

// Scripts/UI/Components/DamageIndicator.gd
class_name DamageIndicator
extends Control

func show_damage_direction(direction: Vector3) -> void
func show_warning(text: String, duration: float) -> void
func hide_warning() -> void
```

---

## 📊 모듈화 우선순위 매트릭스

| 모듈 | 복잡도 | 재사용성 | 영향도 | 우선순위 |
|------|--------|----------|--------|----------|
| ProjectilePoolSystem | 중 | 높음 | 낮음 | 🔥 즉시 |
| MissilePoolSystem | 낮음 | 중간 | 낮음 | 🔥 즉시 |
| AircraftRegistry | 높음 | 높음 | 중간 | ⚡ 높음 |
| AIThreadScheduler | 높음 | 높음 | 중간 | ⚡ 높음 |
| MassPhysicsCalculator | 매우 높음 | 높음 | 높음 | ⏰ 중간 |
| MassRenderSystem | 높음 | 중간 | 중간 | ⏰ 중간 |
| InputRebindHandler | 중간 | 낮음 | 낮음 | 🔵 낮음 |
| FlightInstruments | 낮음 | 중간 | 낮음 | 🔵 낮음 |

---

## 🚀 Quick Start Guide

### Phase 2 시작하기

**Step 1: ProjectilePoolSystem 분리**
```bash
# 1. 새 파일 생성
touch Scripts/Flight/Systems/ProjectilePoolSystem.gd

# 2. FlightManager.gd에서 코드 이동
# - class ProjectileData
# - _projectile_data, _projectile_pool
# - _multi_mesh_instance, _shader_material
# - _setup_multimesh()
# - spawn_projectile()
# - projectile update logic in _physics_process

# 3. FlightManager에서 사용
var projectile_system: ProjectilePoolSystem
projectile_system = ProjectilePoolSystem.new()
add_child(projectile_system)

# 4. 테스트
# - 발사 테스트
# - 충돌 테스트
# - 풀 재사용 테스트
```

---

## 📝 체크리스트

### Phase 2 준비 완료 여부

- [x] FlightManager.gd 코드 분석 완료
- [x] 모듈화 대상 식별 완료
- [x] 모듈 인터페이스 설계 완료
- [ ] 성능 벤치마크 준비
- [ ] 단위 테스트 프레임워크 준비
- [ ] Git 브랜치 생성 (feature/phase2-modularization)

---

**문서 작성 완료**: 2025-12-18T03:03:41Z  
**다음 단계**: Phase 2 실행 계획 수립 및 개발 시작
