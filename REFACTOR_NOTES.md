# 리팩토링 완료 요약

## 1. 공통 계산 모듈 분리

### FlightPhysics.gd
항공역학 관련 계산을 모듈화:
- `calculate_target_speed()` - 스로틀 기반 목표 속도 계산
- `calculate_drag()` - 공기 저항 계산
- `calculate_lift()` - 양력 계산
- `apply_pitch/roll/yaw_rotation()` - 회전 적용
- `calculate_crash_rotation()` - 추락 시 회전 계산
- `check_landing_conditions()` - 착륙 조건 확인
- `calculate_angle_of_attack()` - 받음각 계산
- `calculate_stall_factor()` - 실속 계수 계산
- `calculate_turn_radius()` - 선회 반경 계산
- `calculate_g_force()` - G-Force 계산

### DamageSystem.gd
데미지 시스템 관련 계산을 모듈화:
- `calculate_performance_factors()` - 파츠 체력 기반 성능 계산
- `determine_hit_part()` - 피격 위치 기반 파츠 판정
- `check_wing_destruction()` - 날개 파괴 조건 확인
- `get_part_node_name()` - 파츠 이름 → 노드 이름 매핑
- `check_critical_damage()` - 치명적 데미지 확인
- `calculate_damage_severity()` - 데미지 정도 계산
- `get_repair_priority()` - 수리 우선순위 반환

## 2. Aircraft.gd 리팩토링
- FlightPhysics와 DamageSystem 모듈 사용
- 코드 간소화 및 가독성 향상
- 재사용 가능한 로직 분리

## 3. _physics_process 2번 호출 이슈
현재 디버그 코드가 이미 있음:
```gdscript
var _physics_call_count: int = 0
var _physics_call_timer: float = 0.0
```

테스트 필요:
- 실제로 2배 호출되는지 확인
- 로그 출력으로 검증

## 다음 단계
1. 프로젝트 실행하여 _physics_process 호출 횟수 확인
2. 문제 발견 시 원인 파악 및 수정
3. 디버그 print 문 정리
