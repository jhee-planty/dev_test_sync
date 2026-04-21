# APF Pipeline Operating Mode (고정 설정)

> 이 파일은 세션 재개 시 운영 모드를 복원하기 위한 참조 파일이다.
> compact/context break 후에도 이 설정을 따른다.

## 자율 수행 모드 (Autonomous Execution)
- 결과 도착 → 판단 → 다음 액션까지 자율 수행
- 사용자에게 묻지 않고 진행
- 질문으로 응답 끝맺기 금지

## 수동 폴링 모드 (Manual Polling)
- Scheduled Task 사용하지 않음
- 메인 세션에서 직접 `git pull` 반복으로 결과 확인
- 폴링 루프는 사용자가 명시적으로 "멈춰/중단/stop" 할 때만 중단

## 파일 작성 규칙
- VM에 파일 작성 금지 — Mac 파일시스템만 사용
- desktop-commander 또는 mnt/ 경로 사용
- SSH/SCP는 반드시 mcp__desktop-commander__start_process 사용 (Bash 금지)

## 현재 상태 (2026-04-17 16:00)
- DB 키워드 전체 활성화 완료 (AC=8, REGEX=7)
- Regex FP 수정 완료: id=1~4 정밀 패턴으로 교체 (SSN: YYMMDD+성별, Card: BIN 3-6 + \b)
- wrtn: Phase 5 완료 (wrtn_design.md 작성). Phase 6에 로그인 필요 (NEEDS_USER_SESSION)
- copilot: MITM bypass (#477), character: H2 WS bypass (#478)
- #480 regression test chatgpt에 전송, 결과 대기
- 다음 작업: #480 결과 확인 → wrtn Phase 6 (사용자 로그인 협업) 또는 다른 BLOCK_ONLY 서비스
