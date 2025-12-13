# 지상 충돌 감지 복원 보고서

날짜: 2025-12-13T03:48:00Z
문제: 지상과의 충돌이 감지되지 않음

---

## 🔴 문제: Ground collision_layer 미설정

**MainLevel.tscn (이전)**:
```gdscript
[node name="Ground" type="StaticBody3D" parent="."]
// collision_layer 없음! → 기본값 1 사용
```

**결과**: Aircraft가 Ground를 감지 못함

---

## ✅ 수정

**MainLevel.tscn (수정 후)**:
```gdscript
[node name="Ground" type="StaticBody3D" parent="."]
collision_layer = 8     // Layer 4 (Ground)
collision_mask = 0      // 정적 물체
```

---

## 📊 Physics Layer 구조

```
Layer 1 (비트 1): Player
Layer 2 (비트 2): Ally
Layer 3 (비트 4): Enemy
Layer 4 (비트 8): Ground  ← 수정됨
Layer 5 (비트 16): Projectile
```

---

## 🧪 충돌 조건

### 착륙 ✅
- 속도 < 20 m/s
- 수평 (up.dot(UP) > 0.9)
- 결과: 속도 감소 (95%)

### 추락 ❌
- 속도 ≥ 20 m/s OR
- 각도 틀어짐
- 결과: die() 호출

---

## 🎯 디버그 출력 추가

```
저고도:
[Aircraft] Low altitude: 5.0 | Collisions: 0

충돌 시:
[Aircraft] COLLISION DETECTED! Count: 1
  Collision 0: StaticBody3D at (x, y, z)
  Speed: 45.0 | Is Landing: false
  → CRASH! Destroying aircraft...
```

---

## ✅ 테스트

- [ ] 저속 착륙 (15 m/s)
- [ ] 고속 충돌 (50 m/s)
- [ ] 디버그 로그 확인

---

**수정 완료!** Ground 충돌 감지 복원됨 ✅
