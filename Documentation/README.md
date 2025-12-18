# 📚 Documentation Index

이 폴더에는 프로젝트의 모든 기술 문서가 포함되어 있습니다.

---

## 🔥 최신 문서 (2025-12-18)

### 모듈화 평가 시리즈
1. **[MODULARIZATION_SUMMARY_KR.md](MODULARIZATION_SUMMARY_KR.md)** ⭐ **시작하기 좋음**
   - 한국어 요약 보고서
   - 핵심 내용만 간단히 정리
   - 경영진 / PM용

2. **[MODULARIZATION_ASSESSMENT.md](MODULARIZATION_ASSESSMENT.md)**
   - 종합 평가 보고서 (영문)
   - 상세한 분석과 권장사항
   - 개발자용

3. **[MODULARIZATION_OPPORTUNITIES.md](MODULARIZATION_OPPORTUNITIES.md)**
   - 구체적인 모듈화 대상 코드 식별
   - 코드 라인 단위 분석
   - 리팩토링 가이드

4. **[MODULARIZATION_ARCHITECTURE.md](MODULARIZATION_ARCHITECTURE.md)**
   - 아키텍처 다이어그램
   - 데이터 플로우
   - 의존성 그래프

5. **[MODULARIZATION_COMPARISON.md](MODULARIZATION_COMPARISON.md)**
   - 전후 비교표
   - ROI 계산
   - 성능 영향 분석

---

## 📖 기존 문서

### 모듈화 관련
- **[MODULARIZATION_PLAN.md](MODULARIZATION_PLAN.md)**
  - Phase 1 완료 기록
  - Aircraft 컴포넌트 분리 결과

### 최적화 관련
- **[LARGE_SCALE_OPTIMIZATION_README.md](LARGE_SCALE_OPTIMIZATION_README.md)**
  - 1000+ 기체 지원 시스템
- **[OPTIMIZATION_COMPLETE.md](OPTIMIZATION_COMPLETE.md)**
  - 최적화 완료 보고서
- **[ADVANCED_OPTIMIZATION_COMPLETE.md](ADVANCED_OPTIMIZATION_COMPLETE.md)**
  - 고급 최적화 기법
- **[OPTIMIZATION_RECOMMENDATIONS_DETAILED.md](OPTIMIZATION_RECOMMENDATIONS_DETAILED.md)**
  - 상세 최적화 권장사항

### 코드 리뷰
- **[CODE_REVIEW_REPORT.md](CODE_REVIEW_REPORT.md)**
  - 코드 검수 완료 보고서

### 버그 수정
- **[FLIGHT_FIX_FALLING.md](FLIGHT_FIX_FALLING.md)**
  - 비행기 추락 문제 수정
- **[FLIGHT_FIX_VERTICAL_AI.md](FLIGHT_FIX_VERTICAL_AI.md)**
  - AI 수직 비행 문제 해결
- **[GROUND_COLLISION_FIX.md](GROUND_COLLISION_FIX.md)**
  - 지상 충돌 감지 수정
- **[HOTFIX_MULTIMESH.md](HOTFIX_MULTIMESH.md)**
  - MultiMesh 핫픽스
- **[HOTFIX_REPORT.md](HOTFIX_REPORT.md)**
  - 핫픽스 종합 보고서
- **[PHYSICS_DEATH_SPIRAL_FIX.md](PHYSICS_DEATH_SPIRAL_FIX.md)**
  - 물리 데스 스파이럴 수정
- **[MISSILE_TRAIL_FIX.md](MISSILE_TRAIL_FIX.md)**
  - 미사일 트레일 수정

### 시스템 분석
- **[FLIGHT_PHYSICS_COMPARISON.md](FLIGHT_PHYSICS_COMPARISON.md)**
  - 비행 물리 비교 분석
- **[FLIGHT_PHYSICS_REVIEW.md](FLIGHT_PHYSICS_REVIEW.md)**
  - 비행 물리 검토
- **[PROJECTILE_DAMAGE_REVIEW.md](PROJECTILE_DAMAGE_REVIEW.md)**
  - 발사체 데미지 시스템 검토
- **[GROUND_VEHICLE_SYSTEM.md](GROUND_VEHICLE_SYSTEM.md)**
  - 지상 차량 시스템 문서

### 기타
- **[REFACTOR_NOTES.md](REFACTOR_NOTES.md)**
  - 리팩토링 노트
- **[flight_combat_game_spec.md](flight_combat_game_spec.md)**
  - 게임 사양서

---

## 📊 문서 분류

### 읽기 쉬운 순서 (추천)
1. ⭐ MODULARIZATION_SUMMARY_KR.md (5분)
2. MODULARIZATION_COMPARISON.md (10분)
3. MODULARIZATION_ARCHITECTURE.md (15분)
4. MODULARIZATION_ASSESSMENT.md (30분)
5. MODULARIZATION_OPPORTUNITIES.md (1시간)

### 역할별 추천
- **경영진 / PM**: MODULARIZATION_SUMMARY_KR.md
- **팀 리더**: MODULARIZATION_ASSESSMENT.md, MODULARIZATION_COMPARISON.md
- **개발자**: MODULARIZATION_OPPORTUNITIES.md, MODULARIZATION_ARCHITECTURE.md
- **신규 팀원**: flight_combat_game_spec.md → MODULARIZATION_SUMMARY_KR.md

### 주제별
- **모듈화**: MODULARIZATION_*.md (6개)
- **최적화**: OPTIMIZATION_*.md, LARGE_SCALE_*.md (4개)
- **버그 수정**: *_FIX.md, HOTFIX_*.md (7개)
- **시스템 분석**: *_REVIEW.md, *_COMPARISON.md (4개)

---

## 🔍 Quick Reference

### 모듈화 현황
- **Phase 1**: ✅ 완료 (Aircraft)
- **Phase 2**: ⏸️ 대기 (FlightManager)
- **Phase 3**: ⏸️ 대기 (MassAircraftSystem)

### 주요 메트릭스
- **평균 파일 크기**: 564 lines → 189 lines 목표 (-66%)
- **코드 품질**: B+ → A+ 목표
- **성능 영향**: < 2% (허용 가능)
- **ROI**: 157% (6개월 기준)

### 다음 단계
1. ProjectilePoolSystem 분리 (2일)
2. MissilePoolSystem 분리 (1일)
3. AircraftRegistry 분리 (3일)
4. AIThreadScheduler 분리 (3일)

---

## 📞 Contact

문서 관련 문의:
- 기술 문의: 개발팀
- 문서 오류: Issue 생성

---

**마지막 업데이트**: 2025-12-18T03:03:41Z
