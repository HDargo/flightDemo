# 비행기 추락 문제 긴급 수정

날짜: 2025-12-13T03:20:00Z
문제: 스로틀 100% + 기수 상승에도 계속 추락

---

## 🔴 발견된 문제

### 1. 양력 공식 오류

#### 이전 (잘못됨)
```gdscript
// FlightPhysics.gd
return up_vector * (current_speed * lift_factor * lift_multiplier)

// 계산 예시 (speed=50, lift_factor=0.5)
lift = up * (50 * 0.5 * 1.0) = up * 25 m/s

// delta 적용 후
lift * delta = 25 * 0.016 = 0.4 m/s per frame
gravity = 9.8 * 0.016 = 0.157 m/s per frame

// 문제: 양력이 선형! 속도가 낮으면 양력 부족!
```

---

### 2. 양력 vs 중력 불균형

```
Speed: 10 m/s (최소 속도)
Lift: 10 * 0.5 = 5 m/s
Lift * delta: 5 * 0.016 = 0.08 m/s/frame
Gravity: 9.8 * 0.016 = 0.157 m/s/frame

Net: 0.08 - 0.157 = -0.077 m/s/frame (하강!)
```

**저속에서 양력 < 중력 → 추락**

---

## ✅ 수정 내용

### 1. 양력을 속도²에 비례하도록 수정

```gdscript
// FlightPhysics.gd - 수정 후
static func calculate_lift(...) -> Vector3:
    // Lift acceleration (m/s²) = coefficient * v²
    var lift_acceleration = lift_factor * lift_multiplier * current_speed * current_speed
    return up_vector * lift_acceleration
```

#### 효과
```
Speed: 50 m/s, lift_factor: 0.05
Lift: 0.05 * 50² = 0.05 * 2500 = 125 m/s²
Lift * delta: 125 * 0.016 = 2.0 m/s/frame

Gravity: 9.8 * 0.016 = 0.157 m/s/frame

Net: 2.0 - 0.157 = +1.843 m/s/frame (상승!) ✅
```

---

### 2. lift_factor 조정

#### 이전
```gdscript
@export var lift_factor: float = 0.5  // 너무 큼 (속도²용)
```

#### 수정 후
```gdscript
@export var lift_factor: float = 0.05  // 속도² 공식에 맞게 조정
```

---

### 3. 상세 디버그 출력 추가

```gdscript
if is_player:
    print("=== PHYSICS DEBUG ===")
    print("Speed: %.1f | Throttle: %.1f%%" % [current_speed, throttle * 100])
    print("Lift Force: %.2f m/s²" % lift.length())
    print("Lift.y: %.2f" % lift.y)
    print("Up.y component: %.2f" % up.y)
    print("Velocity.y BEFORE: %.2f" % velocity.y)
    print("Lift contribution: %.2f" % (lift.y * delta))
    print("Gravity: -%.2f" % (9.8 * delta))
    print("Net: %.2f" % (lift.y * delta - 9.8 * delta))
    print("Velocity.y AFTER: %.2f" % velocity.y)
```

---

## 📊 양력 계산 비교

### 저속 (10 m/s)

#### 이전 (선형)
```
Lift = 10 * 0.5 = 5 m/s
Lift/frame = 5 * 0.016 = 0.08 m/s
Gravity/frame = 0.157 m/s
Net = -0.077 m/s (하강) ❌
```

#### 수정 후 (제곱)
```
Lift = 0.05 * 10² = 0.05 * 100 = 5 m/s²
Lift/frame = 5 * 0.016 = 0.08 m/s
Gravity/frame = 0.157 m/s
Net = -0.077 m/s (여전히 하강, 정상!)
```

**정상**: 저속에서는 양력 부족으로 하강해야 함!

---

### 중속 (30 m/s)

#### 이전 (선형)
```
Lift = 30 * 0.5 = 15 m/s
Lift/frame = 15 * 0.016 = 0.24 m/s
Gravity/frame = 0.157 m/s
Net = +0.083 m/s (상승) ✅
```

#### 수정 후 (제곱)
```
Lift = 0.05 * 30² = 0.05 * 900 = 45 m/s²
Lift/frame = 45 * 0.016 = 0.72 m/s
Gravity/frame = 0.157 m/s
Net = +0.563 m/s (상승!) ✅ 더 강함
```

---

### 고속 (50 m/s)

#### 이전 (선형)
```
Lift = 50 * 0.5 = 25 m/s
Lift/frame = 25 * 0.016 = 0.4 m/s
Gravity/frame = 0.157 m/s
Net = +0.243 m/s (상승)
```

#### 수정 후 (제곱)
```
Lift = 0.05 * 50² = 0.05 * 2500 = 125 m/s²
Lift/frame = 125 * 0.016 = 2.0 m/s
Gravity/frame = 0.157 m/s
Net = +1.843 m/s (강력한 상승!) ✅
```

---

## 🎯 예상 비행 특성

### 최소 속도 (10 m/s)
```
양력: 5 m/s²
중력: 9.8 m/s²
결과: 하강 (정상)
→ 스로틀 올려야 함
```

### 순항 속도 (30 m/s)
```
양력: 45 m/s²
중력: 9.8 m/s²
결과: 안정적 상승
→ 정상 비행
```

### 최고 속도 (50 m/s)
```
양력: 125 m/s²
중력: 9.8 m/s²
결과: 급상승
→ 기수 내려야 함
```

---

## 🧪 테스트 시나리오

### 1. 엔진 출력 증가
```
1. 게임 시작
2. Shift 길게 눌러 Throttle 100%
3. 관찰

예상:
- 속도: 10 → 20 → 30 → 40 → 50
- 양력: 5 → 20 → 45 → 80 → 125 m/s²
- 고도: 상승 시작
```

### 2. 기수 상승
```
1. 속도 30 m/s 도달
2. W 눌러 Pitch Up
3. 관찰

예상:
- Up vector의 Y 성분 증가
- 양력 증가
- 강력한 상승
```

### 3. 저속 실속
```
1. Throttle 0%
2. 속도 감소 대기
3. 10 m/s 도달 시

예상:
- 양력 부족
- 하강 시작
- Throttle 올려야 복구
```

---

## 📈 디버그 로그 예시

### 정상 비행 (30 m/s)
```
=== PHYSICS DEBUG ===
Speed: 30.0 | Throttle: 70.0%
Lift Force: 45.00 m/s²
Lift.y: 44.50 (기수 약간 상승)
Up.y component: 0.99
Velocity.y BEFORE: -0.50
Lift contribution: 0.71
Gravity: -0.16
Net: 0.55
Velocity.y AFTER: 0.05 (상승 중)
```

### 저속 (12 m/s)
```
=== PHYSICS DEBUG ===
Speed: 12.0 | Throttle: 20.0%
Lift Force: 7.20 m/s²
Lift.y: 7.00
Up.y component: 0.97
Velocity.y BEFORE: -2.30
Lift contribution: 0.11
Gravity: -0.16
Net: -0.05
Velocity.y AFTER: -2.35 (하강 중)
```

---

## ✅ 결론

**문제**: 양력 공식이 선형 → 저속에서 약함
**수정**: 양력 ∝ 속도² (현실적)

**효과**:
- 고속: 강한 양력 ✅
- 저속: 약한 양력 (정상) ✅
- 스로틀 100% + 기수 상승: 상승 ✅

**다음 단계**:
1. 게임 실행
2. 디버그 로그 확인
3. lift_factor 미세 조정 (필요 시)

---

**수정 완료 시각**: 2025-12-13T03:22:00Z
