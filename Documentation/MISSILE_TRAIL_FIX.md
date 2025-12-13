# 미사일 연기 Trail 지속성 수정 (최종)

날짜: 2025-12-13T03:55:00Z

---

## 🔴 근본 원인

**emitting = false의 오해**

```gdscript
// 착각
emitting = false → 새 파티클만 중단, 기존 유지 ❌

// 실제
emitting = false → 기존 파티클도 즉시 삭제 ❌
```

**하지만** reparent 후에는 동작이 다름!

```gdscript
_trail.reparent(scene)
_trail.emitting = false

// Scene에 독립되어 파티클 유지됨! ✅
```

---

## ✅ 최종 해결책

### 템플릿 패턴 + reparent

```gdscript
class Missile:
    var _trail_template: GPUParticles3D  # 템플릿 저장

func _ready():
    _trail_template = get_node("Trail").duplicate()

func launch():
    # Trail 재생성 (reparent되었을 경우)
    if not _trail or _trail.get_parent() != self:
        _trail = _trail_template.duplicate()
        add_child(_trail)
    
    _trail.emitting = true

func explode():
    _trail.emitting = false
    _trail.reparent(scene, false)  # false = 위치 유지
    
    # 1.5초 후 자동 삭제
    var detached = _trail
    create_timer(1.5).timeout.connect(
        func(): detached.queue_free()
    )
    
    _trail = null  # 다음 launch에서 재생성
```

---

## 🎯 핵심

1. **템플릿 저장**: 원본 설정 보존
2. **reparent 사용**: 파티클 상태 유지
3. **재생성 로직**: 무한 재사용 가능

---

## ✅ 효과

- ✅ 연기가 폭발 후 1.5초 유지
- ✅ 무한 발사 가능
- ✅ Pool 완벽 호환

---

**최종 수정 완료!** ✅
