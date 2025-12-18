# 모듈화 아키텍처 다이어그램 (Modularization Architecture Diagram)

**날짜**: 2025-12-18

---

## 현재 아키텍처 (Current Architecture)

```
┌─────────────────────────────────────────────────────────────────┐
│                         FlightManager                           │
│                           (510 lines)                           │
├─────────────────────────────────────────────────────────────────┤
│ - Aircraft Registry                                             │
│ - Projectile Pool + MultiMesh                                  │
│ - Missile Pool                                                  │
│ - AI Thread Management                                          │
│ - Spatial Grid                                                  │
│ - Team Caching                                                  │
│ - Physics Process Loop                                          │
│ - Mass System Integration                                       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       MassAircraftSystem                        │
│                           (612 lines)                           │
├─────────────────────────────────────────────────────────────────┤
│ - PackedArray Data Management                                  │
│ - CPU Physics Calculation (300+ lines)                         │
│ - GPU Compute Shader Setup                                     │
│ - MultiMesh Rendering (6x LOD levels)                          │
│ - Frustum Culling                                              │
│ - Spawn/Destroy Management                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                          Aircraft                               │
│                           (484 lines)                           │
├─────────────────────────────────────────────────────────────────┤
│ + AircraftInputHandler (77 lines) ✅ Modularized               │
│ + AircraftWeaponSystem (128 lines) ✅ Modularized              │
│ - Flight Physics Integration                                    │
│ - Damage System Integration                                     │
│ - Component Management                                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 제안 아키텍처 - Phase 2 완료 후 (Proposed Architecture - After Phase 2)

```
                    ┌──────────────────────┐
                    │   FlightManager      │
                    │    (150 lines)       │
                    │                      │
                    │ - System Orchestration│
                    │ - Initialization     │
                    │ - Main Loop          │
                    └──────────┬───────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
┌───────────────┐     ┌────────────────┐    ┌────────────────┐
│ Projectile    │     │  Missile       │    │  Aircraft      │
│ PoolSystem    │     │  PoolSystem    │    │  Registry      │
│ (150 lines)   │     │  (80 lines)    │    │  (120 lines)   │
├───────────────┤     ├────────────────┤    ├────────────────┤
│ - MultiMesh   │     │ - Pool Mgmt    │    │ - Registration │
│ - Spawn       │     │ - Spawn        │    │ - Data Cache   │
│ - Update      │     │ - Return       │    │ - Team Lists   │
│ - Raycast     │     │ - Prewarm      │    │ - Spatial Grid │
└───────────────┘     └────────────────┘    └────────┬───────┘
                                                      │
                                             ┌────────▼────────┐
                                             │  AIThread       │
                                             │  Scheduler      │
                                             │  (100 lines)    │
                                             ├─────────────────┤
                                             │ - Thread Pool   │
                                             │ - Batch Process │
                                             │ - LOD Updates   │
                                             └─────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     MassAircraftSystem                          │
│                        (250 lines)                              │
├─────────────────────────────────────────────────────────────────┤
│ - Data Management                                              │
│ - Spawn/Destroy                                                │
│ - System Coordination                                          │
└──────────────┬──────────────────────────┬───────────────────────┘
               │                          │
     ┌─────────▼─────────┐      ┌─────────▼──────────┐
     │  MassPhysics      │      │  MassRender        │
     │  Calculator       │      │  System            │
     │  (220 lines)      │      │  (180 lines)       │
     ├───────────────────┤      ├────────────────────┤
     │ - CPU Physics     │      │ - MultiMesh Setup  │
     │ - GPU Compute     │      │ - LOD Management   │
     │ - Collision       │      │ - Frustum Culling  │
     └───────────────────┘      └────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                          Aircraft                               │
│                           (484 lines)                           │
├─────────────────────────────────────────────────────────────────┤
│ Components:                                                     │
│ ├─ AircraftInputHandler (77 lines) ✅                          │
│ ├─ AircraftWeaponSystem (128 lines) ✅                         │
│ └─ Core Flight Logic (279 lines)                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 데이터 플로우 다이어그램 (Data Flow Diagram)

### 현재 시스템 (Current)

```
┌─────────────┐
│   Player    │
│   Input     │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────┐
│            Aircraft                         │
│                                             │
│  Input → Physics → Weapons → Damage        │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│         FlightManager                       │
│                                             │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐ │
│  │Projectile│  │ Missile  │  │ Aircraft  │ │
│  │  Pool    │  │  Pool    │  │ Registry  │ │
│  └─────────┘  └──────────┘  └───────────┘ │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │    AI Thread Management              │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### 제안 시스템 (Proposed)

```
┌─────────────┐
│   Player    │
│   Input     │
└──────┬──────┘
       │
       ▼
┌────────────────────────────────────────────┐
│       AircraftInputHandler (Component)     │
└──────────────┬─────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│            Aircraft (Core)                  │
│                                             │
│  Input States → Physics → Components       │
└──────┬──────────────────────┬───────────────┘
       │                      │
       │                      ▼
       │         ┌────────────────────────────┐
       │         │ AircraftWeaponSystem       │
       │         │       (Component)          │
       │         └──────────┬─────────────────┘
       │                    │
       ▼                    ▼
┌──────────────────────────────────────────────┐
│           FlightManager (Orchestrator)       │
└──────┬───────────┬───────────┬───────────────┘
       │           │           │
       ▼           ▼           ▼
┌────────────┐ ┌─────────┐ ┌──────────────┐
│Projectile  │ │ Missile │ │  Aircraft    │
│ Pool       │ │ Pool    │ │  Registry    │
│ System     │ │ System  │ └──────┬───────┘
└────────────┘ └─────────┘        │
                                   ▼
                            ┌──────────────┐
                            │ AIThread     │
                            │ Scheduler    │
                            └──────────────┘
```

---

## 모듈 간 의존성 그래프 (Module Dependency Graph)

### Phase 2 후 (After Phase 2)

```
                    FlightManager
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    Projectile      Missile        Aircraft
    PoolSystem      PoolSystem      Registry
                                        │
                                        ▼
                                   SpatialGrid
                                        │
                                        ▼
                                   AIThread
                                   Scheduler
                                        │
                                        ▼
                                  AIController
                                        │
                                        ▼
                                    Aircraft
                                        │
                    ┌───────────────────┼─────────────┐
                    │                   │             │
                    ▼                   ▼             ▼
              Input Handler     Weapon System   Damage System
              (Component)       (Component)      (Utility)
                                      │
                                      ▼
                                FlightPhysics
                                  (Utility)

Legend:
├─ Direct Dependency
▼  Uses / Depends On
```

---

## 성능 영향 분석 (Performance Impact Analysis)

### 함수 호출 체인 비교

**현재 (Current)**:
```
Player Input
  → Aircraft._physics_process()
    → Aircraft.calculate_physics()
    → FlightManager.spawn_projectile()
      → FlightManager._process_projectile_raycast()
```

**제안 (Proposed)**:
```
Player Input
  → AircraftInputHandler.process_input()  [+1 call]
  → Aircraft._physics_process()
    → Aircraft.calculate_physics()
    → AircraftWeaponSystem.process_weapons()  [+1 call]
      → FlightManager.spawn_projectile()  [Delegate]
        → ProjectilePoolSystem.spawn_projectile()  [+1 call]
          → ProjectilePoolSystem._process_raycast()  [+1 call]

Additional Overhead: ~4 function calls per frame
Estimated Impact: < 0.1ms per frame (@ 1000 aircraft)
```

---

## 메모리 레이아웃 비교 (Memory Layout Comparison)

### 현재 (Current)

```
FlightManager Instance
├─ aircrafts: Array[Node]                 ~8KB
├─ ai_controllers: Array[Node]            ~2KB
├─ _projectile_data: Array[ProjectileData] ~200KB
├─ _projectile_pool: Array[ProjectileData] ~100KB
├─ _missile_pool: Array[Missile]          ~50KB
├─ _aircraft_data_map: Dictionary         ~80KB
├─ _allies_list: Array[Dictionary]        ~20KB
├─ _enemies_list: Array[Dictionary]       ~20KB
├─ spatial_grid: SpatialGrid              ~30KB
└─ _aircraft_positions: PackedVector3Array ~12KB
Total: ~522KB
```

### 제안 (Proposed)

```
FlightManager Instance
├─ projectile_system: ProjectilePoolSystem
│  ├─ _projectile_data                    ~200KB
│  ├─ _projectile_pool                    ~100KB
│  └─ _multi_mesh_instance               ~10KB
│
├─ missile_system: MissilePoolSystem
│  └─ _missile_pool                       ~50KB
│
├─ aircraft_registry: AircraftRegistry
│  ├─ aircrafts                           ~8KB
│  ├─ _aircraft_data_map                  ~80KB
│  ├─ _allies_list                        ~20KB
│  ├─ _enemies_list                       ~20KB
│  ├─ spatial_grid                        ~30KB
│  └─ _aircraft_positions                 ~12KB
│
└─ ai_scheduler: AIThreadScheduler
   └─ ai_controllers                      ~2KB

Total: ~532KB (+10KB overhead for Node instances)
Memory Overhead: ~1.9%
```

---

## 테스트 전략 (Testing Strategy)

### 유닛 테스트 범위

```
ProjectilePoolSystem
├─ test_spawn_projectile()
├─ test_pool_recycling()
├─ test_max_capacity()
├─ test_raycast_collision()
└─ test_shader_update()

MissilePoolSystem
├─ test_spawn_missile()
├─ test_return_missile()
├─ test_pool_prewarm()
└─ test_invalid_target()

AircraftRegistry
├─ test_register_aircraft()
├─ test_unregister_aircraft()
├─ test_get_enemies_of()
├─ test_spatial_query()
└─ test_cache_update()

AIThreadScheduler
├─ test_register_ai()
├─ test_batch_processing()
├─ test_distance_lod()
└─ test_thread_cleanup()
```

---

## 마이그레이션 체크리스트 (Migration Checklist)

### Phase 2.1: ProjectilePoolSystem

- [ ] 1. 새 파일 생성: `Scripts/Flight/Systems/ProjectilePoolSystem.gd`
- [ ] 2. ProjectileData 클래스 이동
- [ ] 3. _setup_multimesh() 메서드 이동
- [ ] 4. spawn_projectile() 메서드 이동
- [ ] 5. projectile update 로직 이동
- [ ] 6. FlightManager에서 시스템 인스턴스화
- [ ] 7. 기존 호출 경로 업데이트
- [ ] 8. 단위 테스트 작성
- [ ] 9. 통합 테스트
- [ ] 10. 성능 벤치마크

### Phase 2.2: MissilePoolSystem

- [ ] 1. 새 파일 생성: `Scripts/Flight/Systems/MissilePoolSystem.gd`
- [ ] 2. _missile_pool 변수 이동
- [ ] 3. spawn_missile() 메서드 이동
- [ ] 4. return_missile() 메서드 이동
- [ ] 5. prewarm 기능 추가
- [ ] 6. FlightManager 통합
- [ ] 7. 테스트 및 검증

### Phase 2.3: AircraftRegistry

- [ ] 1. 새 파일 생성: `Scripts/Flight/Systems/AircraftRegistry.gd`
- [ ] 2. aircrafts 배열 이동
- [ ] 3. _aircraft_data_map 이동
- [ ] 4. spatial_grid 통합
- [ ] 5. team lists 로직 이동
- [ ] 6. register/unregister 메서드
- [ ] 7. 캐싱 로직 이동
- [ ] 8. FlightManager 통합
- [ ] 9. 테스트 및 검증

### Phase 2.4: AIThreadScheduler

- [ ] 1. 새 파일 생성: `Scripts/Flight/Systems/AIThreadScheduler.gd`
- [ ] 2. ai_controllers 배열 이동
- [ ] 3. _process_ai_batch 로직 이동
- [ ] 4. 거리 LOD 로직 이동
- [ ] 5. FlightManager 통합
- [ ] 6. 테스트 및 검증

---

## 롤백 계획 (Rollback Plan)

각 Phase마다 Git 브랜치 생성:
```bash
git checkout -b feature/phase2-1-projectile-pool
git checkout -b feature/phase2-2-missile-pool
git checkout -b feature/phase2-3-aircraft-registry
git checkout -b feature/phase2-4-ai-scheduler
```

문제 발생 시:
1. 해당 브랜치로 돌아가기
2. 이전 커밋으로 revert
3. 문제 분석 및 수정
4. 다시 테스트

---

**다이어그램 작성 완료**: 2025-12-18T03:03:41Z
