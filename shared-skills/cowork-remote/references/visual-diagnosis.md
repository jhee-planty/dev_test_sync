# L3 시각 진단 — AnyDesk 스크린샷 기반 test PC 상태 확인

## 왜 필요한가

git polling(L1)과 SSH 로그(L2)만으로는 test PC 클라이언트 측 상태를 알 수 없다.
"브라우저가 열려있는지", "경고가 표시되었는지", "세션이 죽었는지" — 이 질문에
스크린샷 한 장이 즉시 답을 준다.

## 전제 조건

- dev PC에 AnyDesk 앱이 설치되어 test PC에 연결된 상태
- computer-use 도구 사용 가능 (메인 세션만 — Scheduled Task에서는 미검증)
- test PC 사용자에게 read-only 모니터링 사전 고지

## 사용 시점

```
L3 에스컬레이션 조건:
  - check-warning 요청 후 30분 이상 결과 미도착
  - pipeline_state.json → monitoring.visual_needed == true
  - 사용자가 직접 "test PC 화면 확인해줘" 요청
```

## 촬영 절차

```
1. AnyDesk 앱을 전면으로 가져오기
   → computer-use: open_application("AnyDesk")
   → 또는 이미 열려있으면 screenshot으로 현재 화면 확인

2. AnyDesk 창이 test PC 데스크톱을 보여주는지 확인
   → 연결 끊김이면 "AnyDesk 연결 끊김" 판정, 종료

3. 스크린샷 촬영 (read-only, 클릭/타이핑 없음)
   → computer-use: screenshot()
   → 이 스크린샷을 분석하여 상태 분류

4. 판정 결과를 pipeline_state.json에 기록
   monitoring.last_visual_check = ISO timestamp
   monitoring.last_visual_result = 분류 결과 문자열
   monitoring.visual_needed = false
```

## 판독 기준

| 화면 상태 | 분류 | 자동 액션 |
|----------|------|----------|
| 경고 문구가 보인다 | `warning_shown_push_fail` | git push 문제 → 사용자에게 "test PC에서 git push 확인" 알림 |
| 브라우저 열림 + AI 서비스 화면 + 입력 없음 | `automation_stalled` | 자동화 오류 → 동일 요청 재전송 |
| 브라우저 열림 + 로그인 페이지 | `session_expired` | 사용자에게 "test PC 로그인 필요" 알림 |
| 바탕화면만 보임 (브라우저 없음) | `browser_not_running` | 자동화 미실행 → 요청 재전송 또는 test PC 세션 확인 |
| AnyDesk "연결 끊김" 표시 | `anydesk_disconnected` | 네트워크/PC 문제 → 사용자에게 "test PC 연결 확인" 알림 |
| 에러 대화상자/팝업 표시 | `error_dialog` | 스크린샷 저장 → 사용자에게 상세 보고 |

## 3가지 모니터링 모드

### Mode 1 — Read-Only Monitor (기본, 자동화에 사용)

스크린샷만 촬영한다. 마우스 클릭, 키보드 입력을 일절 하지 않는다.
사용자가 test PC에서 작업 중이어도 방해하지 않는다.
**파이프라인 자동화에서는 이 모드만 사용한다.**

### Mode 2 — Exclusive Control (사용자 명시적 위임 시만)

사용자가 "test PC 직접 조작해줘", "내가 안 쓰니까 네가 해" 등 명시적으로 위임했을 때만.
AnyDesk를 통해 클릭/타이핑 가능. input collision 위험이 있으므로 사용자 부재 확인 필수.
**스킬이 자동으로 이 모드를 시작하지 않는다.**

### Mode 3 — Hybrid (권장 운영 방식)

```
primary:    git polling (L1) — 항상 동작
secondary:  SSH etap 로그 (L2) — 5분 무응답 시
visual:     AnyDesk 스크린샷 (L3) — 30분 무응답 시 (read-only)
escalation: exclusive control — 사용자 명시적 요청 시에만
```

## 제한사항

| 제한 | 설명 | 대응 |
|------|------|------|
| Scheduled Task 미지원 | computer-use가 Scheduled Task 독립 세션에서 동작하는지 미검증 | 메인 세션에서만 L3 실행 |
| AnyDesk 스케일링 | 원격 데스크톱 해상도와 로컬 창 크기 불일치 시 좌표 부정확 | Mode 1(스크린샷만)에서는 영향 없음 |
| 촬영 레이턴시 | screenshot 1회 ~5-10초 | 빈번한 촬영 불필요 (30분 간격) |
| AnyDesk 미설치 | dev PC에 AnyDesk가 없으면 L3 불가 | L1+L2로 운영, 사용자에게 설치 안내 |

## Phase B 확장 계획 (향후)

Scheduled Task에서 computer-use 도구 사용 가능 여부를 검증한 후:
- Scheduled Task에서 자동 스크린샷 촬영
- 스크린샷 자동 분석 → 상태 분류 → 자동 액션까지 무인 실행
- monitoring.visual_needed 없이 직접 L3 에스컬레이션
