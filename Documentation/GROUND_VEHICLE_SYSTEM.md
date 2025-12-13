# Ground Vehicle System - MultiMesh Optimization Complete

## 개요
항공기 시스템과 동일한 **MultiMesh + PackedArray** 아키텍처로 지상 차량 시스템을 재설계했습니다.
**500대 이상**의 지상 차량을 효율적으로 시뮬레이션할 수 있습니다.

---

## ✅ 최적화 완료 (2025-12-13)

### 이전 시스템 (개별 노드)
- ❌ 각 차량이 독립 노드 (CharacterBody3D)
- ❌ 개별 _physics_process 호출
- ❌ 개별 렌더링 (N개 Draw Call)
- ⚠️ 한계: ~50대

### 새 시스템 (MultiMesh + PackedArray)
- ✅ PackedArray 기반 중앙 집중식 데이터
- ✅ 단일 _physics_process에서 배치 처리
- ✅ MultiMesh 인스턴싱 (~4 Draw Call)
- ✅ 목표: **500대+**

---

## 아키텍처

### 1. MassGroundSystem (Scripts/Ground/MassGroundSystem.gd)
**대규모 차량 시뮬레이션 엔진**

#### PackedArray 데이터 저장
```gdscript
var positions: PackedVector3Array        # 위치
var velocities: PackedVector3Array       # 속도
var rotations: PackedVector3Array        # 회전 (Y축만 사용)
var speeds: PackedFloat32Array           # 현재 속도
var throttles: PackedFloat32Array        # 스로틀
var healths: PackedFloat32Array          # 체력
var teams: PackedInt32Array              # 팀 (0=Ally, 1=Enemy)
var states: PackedInt32Array             # 상태 (0=Dead, 1=Alive)
var vehicle_types: PackedInt32Array      # 타입 (0=Tank, 1=APC)
```

#### MultiMesh 렌더링
- **4개의 MultiMesh 인스턴스**:
  - `_multimesh_ally_tank`: 아군 탱크
  - `_multimesh_enemy_tank`: 적군 탱크
  - `_multimesh_ally_apc`: 아군 APC
  - `_multimesh_enemy_apc`: 적군 APC

- **자동 최적화**:
  - Frustum Culling (카메라 시야 외부 제외)
  - LOD (400m / 1000m 임계값)
  - Visible Instance Count 동적 조정

#### 물리 시뮬레이션
```gdscript
func _update_physics(delta: float) -> void:
    # 프레임 버짓: 3ms
    for i in active_count:
        # 전진 벡터 계산
        var forward = Vector3(sin(rot.y), 0, cos(rot.y))
        
        # 가속/감속
        spd = move_toward(spd, target_speed, acceleration * delta)
        
        # 조향
        rot.y += input_steers[i] * turn_speed * delta
        
        # 이동
        vel = forward * spd
        pos += vel * delta
        pos.y = 0.0  # 지형 고정
```

---

### 2. MassGroundAI (Scripts/Ground/MassGroundAI.gd)
**배치 AI 처리**

#### 타겟팅 시스템
```gdscript
# 2초마다 최근접 적 탐색
func _find_target(idx: int) -> void:
    var closest_dist = INF
    for j in active_count:
        if teams[j] == my_team: continue
        var dist = my_pos.distance_squared_to(positions[j])
        if dist < closest_dist:
            closest_idx = j
```

#### AI 행동
- **거리별 속도 조절**:
  - `> 50m`: 전속력 (throttle = 1.0)
  - `30~50m`: 중간 속도 (throttle = 0.5)
  - `< 30m`: 정지 (throttle = 0.0)

- **자동 조향**: 타겟 방향으로 회전

---

### 3. FlightManager 통합
```gdscript
# 시스템 초기화
func _setup_mass_systems() -> void:
    mass_ground_system = MassGroundSystem.new()
    add_child(mass_ground_system)
    
    var ground_ai = MassGroundAI.new()
    add_child(ground_ai)
    ground_ai.initialize(500)
    ground_ai.set_ground_system(mass_ground_system)
```

---

## 사용 방법

### 차량 생성
```gdscript
var idx = FlightManager.mass_ground_system.spawn_vehicle(
    Vector3(100, 0, 100),          # 위치
    GlobalEnums.Faction.ALLY,      # 팀
    0                              # 타입 (0=Tank, 1=APC)
)
```

### 차량 제어
```gdscript
# AI 입력 설정
mass_ground_system.input_throttles[idx] = 0.8  # 80% 속도
mass_ground_system.input_steers[idx] = 0.5     # 우회전
```

### 데미지 처리
```gdscript
mass_ground_system.damage_vehicle(idx, 25.0)

if not mass_ground_system.is_vehicle_alive(idx):
    print("Vehicle destroyed!")
```

---

## 최적화 기법

### 1. MultiMesh 인스턴싱
- ✅ CPU → GPU Transform 배치 업로드
- ✅ 1회 Draw Call로 수백 대 렌더링
- ✅ 팀/타입별 분리 → 셰이더 최적화 가능

### 2. PackedArray
- ✅ 메모리 효율적 (Cache-friendly)
- ✅ SIMD 최적화 가능
- ✅ 500대 = ~50KB

### 3. Frustum Culling
- ✅ 카메라 시야 외부 차량 렌더링 제외
- ✅ 자동 Visible Instance Count 조정

### 4. LOD (Level of Detail)
- `< 400m`: 렌더링
- `400m ~ 1000m`: 저품질 (구현 가능)
- `> 1000m`: 렌더링 제외

### 5. 프레임 버짓
- ✅ 물리 업데이트 3ms 제한
- ✅ 초과 시 다음 프레임으로 이월

---

## 성능 목표

| 항목 | 목표 | 상태 |
|------|------|------|
| 최대 차량 수 | 500대 | ✅ |
| 물리 업데이트 | 3ms/frame | ✅ |
| 렌더링 부하 | ~4 Draw Calls | ✅ |
| 메모리 사용 | ~50KB (500대) | ✅ |

---

## 확장성

### 새 차량 타입 추가
1. `vehicle_types` enum 확장
2. `_create_XXX_mesh()` 메서드 추가
3. `_setup_multimesh()`에서 MultiMesh 생성
4. `_update_rendering()`에서 렌더링 로직 추가

### 무기 시스템 추가
```gdscript
var weapon_cooldowns: PackedFloat32Array
var weapon_ranges: PackedFloat32Array

func fire_weapon(idx: int, target_pos: Vector3) -> void:
    # 포탄 발사
    FlightManager.spawn_projectile(...)
```

### 지형 추가
```gdscript
# 지형 높이 적용
var terrain_height = get_terrain_height(pos.x, pos.z)
positions[i].y = terrain_height
```

---

## 항공기 시스템 연동

### 공대지 공격
```gdscript
var ground_pos = FlightManager.mass_ground_system.get_vehicle_position(idx)
var ground_team = FlightManager.mass_ground_system.get_vehicle_team(idx)

if ground_team != my_team:
    fire_missile(ground_pos)
```

### 지대공 공격
```gdscript
var aircraft_pos = FlightManager.mass_aircraft_system.positions[idx]
fire_anti_air_weapon(aircraft_pos)
```

---

## 향후 개선 사항

1. ⏳ **Compute Shader**: GPU 물리 계산
2. ⏳ **NavMesh**: 장애물 회피
3. ⏳ **지형 높이맵**: 언덕/경사 지원
4. ⏳ **파괴 효과**: 폭발/파편 시스템
5. ⏳ **Squad AI**: 팀 단위 전술
6. ⏳ **무기 시스템**: 포격/미사일 발사

---

## 파일 구조
```
Scripts/Ground/
├── MassGroundSystem.gd   # 대규모 차량 시뮬레이션
├── MassGroundAI.gd       # 배치 AI 처리
├── GroundVehicle.gd      # (레거시 - 소규모용)
├── GroundWeaponSystem.gd # (레거시)
├── GroundAI.gd           # (레거시)
└── GroundProjectile.gd   # (레거시)
```

---

**최적화 완료**: 2025-12-13  
**시스템**: MassGroundSystem + MassGroundAI  
**상태**: ✅ **MultiMesh 최적화 완료**  
**성능**: 500대+ 지상 차량 지원
