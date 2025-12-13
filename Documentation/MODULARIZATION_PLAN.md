# 모듈화 계획서

날짜: 2025-12-13T03:58:00Z

---

## 📊 현재 상태 분석

### 파일 크기 분석

```
MassAircraftSystem.gd: 576 lines ⚠️ 매우 큼
Aircraft.gd: 569 lines ⚠️ 매우 큼
FlightManager.gd: 466 lines ⚠️ 큼
AIController.gd: 245 lines ⚠️ 중간
MassAISystem.gd: 202 lines ✅ 적당
LODSystem.gd: 182 lines ✅ 적당
Missile.gd: 176 lines ✅ 적당
FlightPhysics.gd: 142 lines ✅ 적당
CameraRig.gd: 131 lines ✅ 적당
DamageSystem.gd: 118 lines ✅ 적당
```

---

## 🎯 모듈화 우선순위

### Priority 1: Aircraft.gd (569 lines)

**문제점**:
- 입력 처리 (process_player_input, _unhandled_input)
- 물리 계산 (calculate_physics)
- 전투 시스템 (shooting, missiles)
- 타겟 탐색 (threading)
- 충돌 처리
- 데미지 시스템

**모듈 분리 계획**:

```
Aircraft.gd (200 lines)
├─ AircraftInputHandler.gd (100 lines) ← NEW
│  ├─ process_player_input()
│  ├─ _unhandled_input()
│  └─ mouse_input handling
│
├─ AircraftWeaponSystem.gd (150 lines) ← NEW
│  ├─ _deferred_shoot()
│  ├─ _deferred_fire_missile()
│  ├─ _start_target_search()
│  └─ _thread_find_target()
│
└─ (기존) DamageSystem.gd ✅ 이미 모듈화됨
   ├─ take_damage()
   ├─ break_part()
   └─ die()
```

---

### Priority 2: FlightManager.gd (466 lines)

**문제점**:
- MultiMesh 관리
- Projectile Pool
- Missile Pool
- Thread 관리
- 너무 많은 책임

**모듈 분리 계획**:

```
FlightManager.gd (150 lines)
├─ ProjectilePoolSystem.gd (150 lines) ← NEW
│  ├─ MultiMesh 관리
│  ├─ Projectile spawning
│  └─ Raycast collision
│
├─ MissilePoolSystem.gd (80 lines) ← NEW
│  ├─ Missile pool
│  ├─ get_missile()
│  └─ return_missile()
│
└─ AircraftRegistry.gd (100 lines) ← NEW
   ├─ register/unregister_aircraft()
   ├─ spatial_grid
   └─ team lists cache
```

---

### Priority 3: MassAircraftSystem.gd (576 lines)

**문제점**:
- CPU fallback과 GPU system 혼재
- 너무 긴 physics calculation
- LOD와 Occlusion이 섞여있음

**모듈 분리 계획**:

```
MassAircraftSystem.gd (250 lines)
├─ MassPhysicsCalculator.gd (200 lines) ← NEW
│  ├─ calculate_cpu_physics()
│  └─ calculate_gpu_physics()
│
└─ MassRenderingSystem.gd (150 lines) ← NEW
   ├─ update_multimesh()
   ├─ apply_lod()
   └─ occlusion_culling()
```

---

## 📝 모듈화 단계

### Phase 1: Aircraft 모듈화 (가장 시급)

**Step 1.1: AircraftInputHandler 분리**

```gdscript
// Scripts/Flight/Components/AircraftInputHandler.gd
extends Node
class_name AircraftInputHandler

signal pitch_input_changed(value: float)
signal roll_input_changed(value: float)
signal fire_pressed()
signal missile_pressed()
signal throttle_up_pressed()
signal throttle_down_pressed()

@export var mouse_sensitivity: float = 0.002
var mouse_input: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent):
    # Mouse input handling
    pass

func process_input() -> Dictionary:
    # Return input state
    return {
        "pitch": input_pitch,
        "roll": input_roll,
        "fire": input_fire,
        "missile": input_missile
    }
```

**Step 1.2: AircraftWeaponSystem 분리**

```gdscript
// Scripts/Flight/Components/AircraftWeaponSystem.gd
extends Node
class_name AircraftWeaponSystem

@export var fire_rate: float = 0.1
@export var missile_cooldown: float = 2.0
@export var missile_lock_range: float = 2000.0

var last_fire_time: float = 0.0
var last_missile_time: float = 0.0
var locked_target: Node3D = null

func can_fire() -> bool:
    pass

func fire_projectile():
    pass

func fire_missile():
    pass

func find_target():
    pass
```

**Step 1.3: Aircraft.gd 리팩토링**

```gdscript
// Scripts/Flight/Aircraft.gd (simplified)
extends CharacterBody3D
class_name Aircraft

# Components
var input_handler: AircraftInputHandler
var weapon_system: AircraftWeaponSystem
var damage_system: DamageSystem  # Already exists

func _ready():
    _setup_components()

func _setup_components():
    input_handler = AircraftInputHandler.new()
    add_child(input_handler)
    
    weapon_system = AircraftWeaponSystem.new()
    add_child(weapon_system)

func _physics_process(delta):
    if is_player:
        var inputs = input_handler.process_input()
        input_pitch = inputs.pitch
        input_roll = inputs.roll
    
    calculate_physics(delta)
    move_and_slide()
```

---

### Phase 2: FlightManager 모듈화

**Step 2.1: ProjectilePoolSystem 분리**

```gdscript
// Scripts/Flight/Systems/ProjectilePoolSystem.gd
extends Node
class_name ProjectilePoolSystem

var _projectile_data: Array[ProjectileData] = []
var _multi_mesh_instance: MultiMeshInstance3D

func spawn_projectile(pos: Vector3, vel: Vector3, damage: float):
    pass

func update_projectiles(delta: float):
    pass
```

**Step 2.2: MissilePoolSystem 분리**

```gdscript
// Scripts/Flight/Systems/MissilePoolSystem.gd
extends Node
class_name MissilePoolSystem

var _missile_pool: Array[Node] = []

func get_missile() -> Missile:
    pass

func return_missile(m: Missile):
    pass
```

**Step 2.3: AircraftRegistry 분리**

```gdscript
// Scripts/Flight/Systems/AircraftRegistry.gd
extends Node
class_name AircraftRegistry

var aircrafts: Array[Node] = []
var spatial_grid: SpatialGrid
var _aircraft_data_map: Dictionary = {}

func register_aircraft(aircraft: Node):
    pass

func unregister_aircraft(aircraft: Node):
    pass

func get_aircraft_data(node: Node) -> Dictionary:
    pass
```

---

### Phase 3: MassAircraftSystem 모듈화 (선택적)

**조건**: Phase 1, 2 완료 후 필요시 진행

---

## 🎯 예상 효과

### 가독성 ✅
```
Aircraft.gd: 569 → 200 lines (-65%)
FlightManager.gd: 466 → 150 lines (-68%)
```

### 유지보수성 ✅
- 각 모듈이 단일 책임
- 테스트 용이
- 버그 격리

### 재사용성 ✅
```
AircraftInputHandler → Ground Vehicle에서도 사용 가능
AircraftWeaponSystem → 다른 비행기 타입에 재사용
ProjectilePoolSystem → 다른 프로젝트에 이식 가능
```

---

## ⚠️ 주의사항

### 성능 영향 최소화

**Good**:
```gdscript
# 컴포넌트를 자식으로 추가 (씬 트리 내)
add_child(input_handler)
# → 엔진 최적화 혜택
```

**Bad**:
```gdscript
# 참조만 저장 (씬 트리 밖)
input_handler = AircraftInputHandler.new()
# → 메모리 관리 복잡
```

### Signal 대신 직접 호출

**Good (빠름)**:
```gdscript
var inputs = input_handler.process_input()
input_pitch = inputs.pitch
```

**Bad (느림)**:
```gdscript
input_handler.pitch_changed.connect(_on_pitch_changed)
# → Signal overhead
```

---

## 📅 실행 계획

### Week 1: Phase 1 - Aircraft 모듈화
- Day 1-2: AircraftInputHandler 생성 및 테스트
- Day 3-4: AircraftWeaponSystem 생성 및 테스트
- Day 5: Aircraft.gd 리팩토링 및 통합 테스트

### Week 2: Phase 2 - FlightManager 모듈화
- Day 1-2: ProjectilePoolSystem 분리
- Day 3: MissilePoolSystem 분리
- Day 4: AircraftRegistry 분리
- Day 5: 통합 테스트 및 버그 수정

### Week 3: 검증 및 최적화
- 성능 테스트
- 메모리 프로파일링
- 1000+ 기체 테스트

---

## 🚀 즉시 시작 가능

**가장 먼저 할 것**: Phase 1, Step 1.1
→ AircraftInputHandler 분리 (가장 간단하고 영향 적음)

---

## ✅ Phase 1 완료! (2025-12-13T04:05:00Z)

### 📊 결과

```
Aircraft.gd: 569 → 447 lines (-122 lines, -21.4%) ✅
├─ AircraftInputHandler.gd: 70 lines (NEW)
└─ AircraftWeaponSystem.gd: 118 lines (NEW)

Total: 447 + 70 + 118 = 635 lines
Overhead: +66 lines (모듈 간 인터페이스 코드)
```

### 🎯 모듈 분리 완료

**1. AircraftInputHandler** ✅
- 키보드/마우스 입력 처리
- 카메라 뷰 토글
- 디버그 키 (T/Y - 날개 파괴)

**2. AircraftWeaponSystem** ✅
- 총기 발사 (fire_rate 관리)
- 미사일 발사 (cooldown 관리)
- 타겟 탐색 (WorkerThreadPool 사용)
- 타겟 락온 (최적화된 각도 계산)

**3. Aircraft (Core)** ✅
- 물리 계산 (FlightPhysics)
- 데미지 시스템 (DamageSystem)
- 컴포넌트 조합 및 관리

### 🔧 통합 방식

```gdscript
// Aircraft.gd
func _setup_components():
    input_handler = AircraftInputHandler.new()
    weapon_system = AircraftWeaponSystem.new()
    add_child(input_handler)
    add_child(weapon_system)

func _physics_process(delta):
    # Get inputs from handler
    if is_player and input_handler:
        input_handler.process_input()
        input_pitch = input_handler.input_pitch
        # ...
    
    calculate_physics(delta)

func _process(delta):
    # Process weapons
    if weapon_system:
        weapon_system.process_weapons(delta, input_fire, input_missile)
        locked_target = weapon_system.locked_target
```

### ✅ 장점

1. **가독성**: 각 모듈이 단일 책임 (SRP)
2. **재사용성**: InputHandler는 Ground Vehicle에도 사용 가능
3. **테스트 용이**: 각 컴포넌트를 독립적으로 테스트
4. **버그 격리**: 입력 문제 → InputHandler만 확인
5. **성능**: 컴포넌트가 씬 트리 자식 → 엔진 최적화

### ⚠️ 주의사항

- Signal 대신 직접 호출 사용 (성능)
- 컴포넌트를 씬 트리에 추가 (add_child)
- Thread 정리는 컴포넌트가 관리

---

## 🔜 다음 단계: Phase 2 - FlightManager 모듈화

**예상 작업**:
- ProjectilePoolSystem 분리 (150 lines)
- MissilePoolSystem 분리 (80 lines)
- AircraftRegistry 분리 (100 lines)

**목표**: FlightManager.gd (466 → 150 lines)

---

**모듈화 계획 수립 완료!** 
시작 준비 완료 ✅

**Phase 1 완료!** 2025-12-13T04:05:00Z ✅
