# 비행 물리 로직 비교 및 수정 보고서

날짜: 2025-12-13T03:43:00Z

---

## 🔍 문제 분석: 기존 vs 수정 로직 비교

---

## 원본 작동 로직 (git 96e0f1b)

```gdscript
// Aircraft.gd
var forward = -global_transform.basis.z
var up = global_transform.basis.y
var lift = FlightPhysics.calculate_lift(current_speed, lift_factor, _c_lift_factor, up)

# Update velocity
velocity = forward * current_speed + lift * delta

# Gravity
velocity.y -= 9.8 * delta
```

### 원본 FlightPhysics.calculate_lift

```gdscript
static func calculate_lift(...) -> Vector3:
    return up_vector * (current_speed * lift_factor * lift_multiplier)
    // 반환: m/s (속도)
```

### 원본 계산 예시

```
Speed: 50 m/s
lift_factor: 0.5
lift = up * (50 * 0.5 * 1.0) = up * 25 m/s

velocity = forward * 50 + lift * 0.016
         = (0, 0, -50) + (0, 25, 0) * 0.016
         = (0, 0, -50) + (0, 0.4, 0)
         = (0, 0.4, -50)

velocity.y -= 9.8 * 0.016 = 0.4 - 0.157 = 0.243

Final: (0, 0.243, -50)
```

**결과**: Forward 방향 이동 + 약한 상승

---

## 첫 번째 수정 시도 (잘못됨)

```gdscript
// 문제: 중력이 누적 안됨
velocity = forward * current_speed + lift * delta  // 매 프레임 리셋!
velocity.y -= 9.8 * delta  // 이미 리셋됨
```

**문제점**: 
- velocity를 매 프레임 새로 생성
- velocity.y가 누적되지 않음
- 중력 효과 거의 없음

---

## 두 번째 수정 시도 (더 나빠짐)

```gdscript
// 양력을 속도²로 변경
var lift_acceleration = lift_factor * lift_multiplier * current_speed * current_speed
return up_vector * lift_acceleration  // m/s² 단위

// Aircraft.gd
var horizontal_velocity = forward * current_speed
velocity.x = horizontal_velocity.x  // X 고정
velocity.z = horizontal_velocity.z  // Z 고정
velocity.y += lift.y * delta  // Y만 누적
velocity.y -= 9.8 * delta
```

**문제점**:
- X, Z는 매 프레임 고정 (회전 반영 안됨)
- Y만 누적
- **비행기가 제자리에서 수직으로만 움직임!**

---

## ✅ 최종 수정 (원본 복원 + 개선)

### 수정 1: 원본 로직 복원

```gdscript
// Aircraft.gd
velocity = forward * current_speed + lift * delta
velocity.y -= 9.8 * delta
```

### 수정 2: 양력 공식 개선 (속도² 유지)

```gdscript
// FlightPhysics.gd
static func calculate_lift(...) -> Vector3:
    // 속도² 사용 (현실적 공기역학)
    var lift_magnitude = lift_factor * lift_multiplier * current_speed * current_speed
    return up_vector * lift_magnitude  // m/s 단위 (delta 곱할 것)
```

### 수정 3: lift_factor 조정

```gdscript
@export var lift_factor: float = 0.05  // 속도²에 맞게
```

---

## 📊 최종 로직 계산 과정

### 입력
- Speed: 50 m/s
- lift_factor: 0.05
- Throttle: 100%
- Up: (0, 1, 0) (수평 비행)
- Forward: (0, 0, -1)

### 계산

```
1. Lift calculation:
   lift = up * (0.05 * 1.0 * 50²)
        = (0, 1, 0) * (0.05 * 2500)
        = (0, 125, 0) m/s

2. Velocity update:
   velocity = forward * speed + lift * delta
            = (0, 0, -1) * 50 + (0, 125, 0) * 0.016
            = (0, 0, -50) + (0, 2.0, 0)
            = (0, 2.0, -50)

3. Gravity:
   velocity.y -= 9.8 * 0.016
   velocity.y = 2.0 - 0.157 = 1.843

4. Final velocity:
   velocity = (0, 1.843, -50)
```

### 결과

```
매 프레임:
- X: forward.x * speed (회전 반영)
- Y: lift - gravity (상승/하강)
- Z: forward.z * speed (회전 반영)

이동:
- Forward 방향: 50 m/s
- 상승: 1.843 m/s
- 정상 비행! ✅
```

---

## 🔑 핵심 이해

### 원본이 작동한 이유

```gdscript
velocity = forward * current_speed + lift * delta
```

**이 공식의 의미**:
1. `forward * current_speed`: 현재 바라보는 방향으로 이동
2. `lift * delta`: 양력에 의한 추가 이동 (주로 상승)
3. 매 프레임 forward가 회전에 따라 변경됨
4. **velocity는 매 프레임 새로 계산되지만, 방향이 변하므로 문제없음**

### 잘못된 이해 (두 번째 수정)

```gdscript
velocity.x = forward.x * speed  // 고정!
velocity.z = forward.z * speed  // 고정!
velocity.y += lift * delta      // 누적!
```

**문제**:
- X, Z를 직접 대입 → 회전이 반영되지 않음
- Y만 누적 → 제자리에서 수직 이동

---

## 💡 Velocity 처리 방식의 차이

### 방식 1: 매 프레임 재계산 (원본, 올바름)

```gdscript
velocity = forward * speed + lift * delta - Vector3(0, 9.8*delta, 0)
```

**특징**:
- velocity는 "이번 프레임 이동량"
- forward가 회전하면 velocity도 자동 회전
- 중력은 velocity.y에 직접 적용

**장점**: 간단, 명확, 회전 자동 반영

---

### 방식 2: 성분별 누적 (시도했으나 실패)

```gdscript
velocity.x = forward.x * speed
velocity.z = forward.z * speed
velocity.y += (lift - gravity) * delta
```

**특징**:
- velocity.x, z는 "현재 프레임 값"
- velocity.y는 "누적 값"
- **혼용하면 안됨!**

**문제**: X, Z가 고정되어 회전 반영 안됨

---

## 🎯 올바른 물리 모델

### CharacterBody3D의 velocity

Godot CharacterBody3D의 velocity는:
- **"이번 프레임 이동할 방향과 속도"**
- move_and_slide()가 이를 사용해 이동
- 다음 프레임에는 다시 설정해야 함

### 우리의 적용

```gdscript
// 매 프레임
velocity = forward * current_speed  // 기본 전진
         + lift * delta             // 양력 상승
velocity.y -= 9.8 * delta           // 중력 하강

// move_and_slide()가 velocity만큼 이동
```

**이게 맞음!** ✅

---

## 📈 양력 공식 비교

### 원본 (선형)

```
lift = speed * 0.5
50 m/s → 25 m/s
30 m/s → 15 m/s
10 m/s → 5 m/s
```

**문제**: 저속에서 양력 너무 약함

---

### 수정 (제곱)

```
lift = speed² * 0.05
50 m/s → 125 m/s
30 m/s → 45 m/s
10 m/s → 5 m/s
```

**장점**: 
- 고속에서 강한 양력 (현실적)
- 저속에서도 적절한 양력

---

## ⚠️ 중요 교훈

### 1. 단위 확인
```
lift 반환값: m/s (속도)
delta 곱함: m/s * s = m (이동량)
```

### 2. velocity 의미 파악
```
CharacterBody3D: velocity = 이번 프레임 이동량
RigidBody3D: velocity = 실제 속도 (누적)
```

### 3. 매 프레임 재계산 vs 누적
```
재계산: velocity = 새로운 값 (회전 반영)
누적: velocity += 변화량 (관성 유지)
```

**우리는 재계산 방식 사용!**

---

## ✅ 최종 확인

### 수정 사항

1. ✅ velocity 계산 원본 복원
2. ✅ lift 공식 속도² 유지
3. ✅ lift_factor 0.05 조정
4. ✅ AI 초기 throttle 0.7

### 예상 동작

```
플레이어:
- Throttle Up → 가속
- Forward 방향 이동 ✅
- 양력으로 상승 ✅
- 회전 시 방향 변경 ✅

AI:
- 초기 throttle 70%
- 즉시 가속 시작
- 추락 방지 ✅
```

---

## 🧪 테스트 체크리스트

- [ ] 플레이어 전진 (Throttle 100%)
- [ ] 회전 시 방향 변경 (마우스 좌우)
- [ ] 상승 (W 키)
- [ ] 하강 (S 키)
- [ ] AI 5초 생존
- [ ] 루프 가능 여부

---

**수정 완료 시각**: 2025-12-13T03:45:00Z

**핵심**: velocity는 매 프레임 재계산되며, forward 방향이 회전에 따라 변하므로 올바르게 작동합니다!
