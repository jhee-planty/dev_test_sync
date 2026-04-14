# Scheduled Task Execution Flow (dev PC)

## Execution Flow (per cron cycle)

```
매 실행 시 (cron):
  0. Recovery scan (매 실행 필수):
     - pipeline_state.json 읽기 (이전 상태 복원)
     - regen-status.sh 실행 → status.md를 impl journal에서 재생성
     - git pull 전에 unpushed commits 확인 → 있으면 push 먼저
     - requests/에 미응답 요청이 있는지 filesystem 스캔
  1. git pull로 최신 상태 동기화 (전송 수단)
     git push 실패 시 3회 재시도: (1) 즉시 재시도, (2) pull --rebase 후 재시도, (3) stash + pull + pop 후 재시도
  2. results/에 새 결과 파일 확인 (filesystem이 권위 있는 소스)
     ※ git pull 결과("Already up to date")와 무관하게 항상 스캔
  3-a. 새 결과 없음 → dashboard 갱신("대기 중") → 종료
  3-b. 새 결과 있음 →
       결과 읽기 → 성공/실패 판단 →
       성공: impl journal 갱신 + 다음 서비스 자동 진행 + git push
            (다음 서비스: service_queue에서 status=="pending_check"인 최상위 우선순위)
       실패: 원인 분석 → 자동 수정 가능 여부 판단 → 액션 실행
       Auto-SUSPEND: §BEHAVIORAL RULES 참조 — 같은 실패 카테고리 3회 연속 시 SUSPENDED.
       Auto-Classify: verdict→status 자동 매핑 (SKILL.md § Auto-Classify 테이블 참조).
  4. pipeline_state.json 갱신 (last_delivered_id 포함)
  5. pipeline_dashboard.md 갱신
  6. macOS 알림 전송 (핵심 이벤트만)
```

## Failure Handling

Scheduled Task는 결과를 감지하고 분석한 후 **다음 액션까지 실행**해야 한다.
감지 → 보고에서 멈추면 사용자 개입이 필요해지므로 "전체 작업자" 목표에 어긋난다.
구체적인 실패 분류, 자동 수정 액션, 3-Strike Rule 등은 Scheduled Task 프롬프트에 정의되어 있다.
