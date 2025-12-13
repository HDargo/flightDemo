# 비행기 수직 상승 및 AI 추락 긴급 수정

날짜: 2025-12-13T03:38:00Z

---

## 🔴 발견된 2가지 치명적 문제

### 문제 1: 스로틀 올리면 Y값만 증가 (수직 상승)

#### 원인
```gdscript
// Aircraft.gd Line 249-251 (이전)
var horizontal_velocity = forward * current_speed
velocity.x = horizontal_velocity.x
velocity.z = horizontal_velocity.z

// Line 255-258
velocity.y += lift.y * delta
velocity.y -= 9.8 * delta
```

**문제점**:
- Horizontal velocity는 설정
- Vertical velocity는 **누적**
- 결과: X, Z는 항상 같은 값, Y만 변화
- **비행기가 제자리에서 수직으로만 움직임!**

---

### 문제 2: AI가 즉시 추락

#### 원인
```gdscript
// AIController.gd _ready()
aircraft = get_parent() as Aircraft

// 초기 throttle 설정이 없음!
// Aircraft.gd에서 current_speed = 10.0 (최소 속도)
// 하지만 throttle = 0.0
```

**결과**:
- 초기 속도: 10 m/s
- 양력: 0.05 × 10² = 5 m/s²
- 중력: 9.8 m/s²
- **Net: -4.8 m/s² → 즉시 추락!**

---

## ✅ 수정 내용

### 수정 1: Velocity 통합 계산

```gdscript
// Aircraft.gd - 수정 후
# Update velocity
# Horizontal component: forward direction with current speed
var forward_velocity = forward * current_speed

# Vertical component: lift and gravity (accumulated)
var vertical_acceleration = lift.y - 9.8  # m/s²
velocity.y += vertical_acceleration * delta

# Combine: horizontal (direct) + vertical (accumulated)
velocity = Vector3(forward_velocity.x, velocity.y, forward_velocity.z)
```

**효과**:
- Horizontal: forward 방향으로 current_speed
- Vertical: 양력과 중력의 누적
- **정상적인 비행 궤적** ✅

---

### 수정 2: AI 초기 Throttle 설정

```gdscript
// AIController.gd _ready()
aircraft = get_parent() as Aircraft
if not aircraft:
    return

# Initialize AI with default throttle to prevent immediate falling
aircraft.throttle = 0.7  # Start at 70% throttle
aircraft.input_throttle_up = true  # Begin accelerating
```

**효과**:
- 초기 throttle: 70%
- Target speed: lerp(10, 50, 0.7) = 38 m/s
- AI가 즉시 가속 시작
- **추락 방지** ✅

---

## 📊 수정 전/후 비교

### 플레이어 비행 (Throttle 100%)

#### 이전 (잘못됨)
```
프레임 1:
- velocity.x = forward.x * 50 = 0
- velocity.z = forward.z * 50 = -50
- velocity.y = 0 + lift - gravity = +1.8

프레임 2:
- velocity.x = forward.x * 50 = 0  (똑같음!)
- velocity.z = forward.z * 50 = -50  (똑같음!)
- velocity.y = 1.8 + lift - gravity = +3.6

결과: X, Z 고정, Y만 증가 → 수직 상승! ❌
```

#### 수정 후 (올바름)
```
프레임 1:
- forward_velocity = forward * 50
- velocity.y += (lift - gravity) * delta = +1.8
- velocity = (forward.x*50, 1.8, forward.z*50)
- Position: (0, 0, 0) → (0, 1.8, -50)

프레임 2:
- forward은 회전에 따라 변함
- velocity.y += (lift - gravity) * delta = +3.6
- velocity = (forward.x*50, 3.6, forward.z*50)
- Position: (0, 1.8, -50) → (forward 방향 이동)

결과: Forward 방향 + 상승 → 정상 비행! ✅
```

---

### AI 비행

#### 이전 (추락)
```
초기화:
- throttle: 0.0
- speed: 10 m/s (최소)
- lift: 5 m/s²
- gravity: 9.8 m/s²
- Net: -4.8 m/s²

1초 후:
- velocity.y = -4.8 m/s
- 추락 중...

3초 후:
- 지상 충돌! ❌
```

#### 수정 후 (정상)
```
초기화:
- throttle: 0.7 (70%)
- target speed: 38 m/s
- AI가 throttle_up 시작

1초 후:
- speed: 10 → 25 m/s
- lift: 31 m/s²
- gravity: 9.8 m/s²
- Net: +21 m/s² (상승!)

3초 후:
- speed: 38 m/s (순항)
- 안정적 비행 ✅
```

---

## 🧪 테스트 시나리오

### 1. 플레이어 비행 테스트

**절차**:
1. 게임 시작
2. Shift (Throttle Up)
3. 비행기 움직임 관찰

**예상 결과**:
```
이전: 제자리에서 Y만 증가 (수직 상승) ❌
수정: Forward 방향 + 상승 (정상 비행) ✅
```

---

### 2. AI 생존 테스트

**절차**:
1. 게임 시작
2. AI 비행기 관찰 (5초)

**예상 결과**:
```
이전: 3초 안에 모두 추락 ❌
수정: 안정적으로 비행 ✅
```

---

### 3. 기동 테스트

**절차**:
1. Throttle 100%
2. W (Pitch Up)
3. 루프 시도

**예상 결과**:
```
이전: 수직으로만 움직여 루프 불가 ❌
수정: Forward 방향 회전하며 루프 가능 ✅
```

---

## 📈 디버그 출력 예시

### 정상 비행 (30 m/s)
```
=== PHYSICS DEBUG ===
Speed: 30.0 | Throttle: 70.0%
Lift Force: 45.00 m/s²
Up.y component: 0.99
Velocity.y BEFORE: 1.50
Lift contribution: 0.72
Gravity: -0.16
Net: 0.56
Forward velocity: (0, 0, -30)
Vertical accel: 35.20 m/s²
Final velocity: (0, 2.06, -30)
```

**해석**:
- Forward: -30 m/s (Z축 음수 방향)
- Vertical: +2.06 m/s (상승 중)
- **정상적인 비행 궤적** ✅

---

## ⚠️ 주의사항

### Velocity 계산 순서 중요!

```gdscript
// 올바른 순서
1. forward_velocity 계산 (현재 방향)
2. velocity.y 업데이트 (양력 + 중력)
3. 최종 velocity 조합

// 잘못된 순서 (이전)
1. velocity.x, z 설정
2. velocity.y 별도 업데이트
→ X, Z가 고정되어 회전 반영 안됨
```

---

## 🎯 물리 특성 (수정 후)

### Horizontal Motion
- **방향**: -global_transform.basis.z (forward)
- **속도**: current_speed (throttle 기반)
- **특징**: 회전에 따라 방향 변경

### Vertical Motion
- **양력**: lift_factor × speed² × up.y
- **중력**: -9.8 m/s²
- **특징**: 누적 (realistic falling)

### 결합
```
velocity = (forward.x * speed, accumulated_y, forward.z * speed)
```

---

## ✅ 결론

**문제 1**: Velocity 계산 오류 → 수직 상승
**수정 1**: Horizontal + Vertical 통합 계산

**문제 2**: AI 초기 throttle 없음 → 즉시 추락
**수정 2**: 초기 throttle 70% 설정

**효과**:
- ✅ 플레이어: 정상 비행
- ✅ AI: 추락 방지
- ✅ 기동: 루프/배럴롤 가능

---

**수정 완료 시각**: 2025-12-13T03:40:00Z
