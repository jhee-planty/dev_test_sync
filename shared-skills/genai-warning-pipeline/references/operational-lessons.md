# 운영 교훈 (세션 회고 반영)

## 확인 안 되는 서비스는 제외하고 진행

여러 서비스 동시 작업 시, 테스트 결과가 확인되지 않는 서비스(자동화 불가,
페이지 미로딩 등)는 **즉시 제외**하고 확인 가능한 서비스부터 완료한다.
막힌 서비스에 시간을 쓰면 전체 파이프라인이 정체된다.

## 컨텍스트 관리 — 작업 중단 방지

대화가 길어지면 컨텍스트 오버플로로 /compact 실패(20MB 제한)가 발생한다.
sub-agent 출력, HAR 내용, 긴 로그가 주요 원인이다.

```
예방 수칙:
  - 50~100턴마다 주기적으로 /compact 실행
  - 대용량 데이터(HAR, 로그)는 대화에 출력하지 말고 파일로 저장 후 경로만 참조
  - sub-agent 결과도 요약만 대화에 포함하고 전문은 파일 저장
```

## Git 동기화 주의사항

Git push/pull 실패 시 대응:
- `git push` 실패 (reject) → `git pull --rebase` 후 재시도
- `git pull` 충돌 → requests/와 results/는 쓰기 방향 분리로 충돌 없어야 정상. 발생 시 원인 파악
- 네트워크 불안정 → 재시도. **동기화 실패가 전체 작업을 멈추게 하면 안 된다**

## 터미널 누적 문제

서버 작업마다 터미널이 추가되어 열린 터미널 수가 계속 증가하는 문제.
etap-build-deploy의 "터미널 사용 규칙"을 준수하되, 불필요한 터미널은
작업 완료 후 정리한다.

## 성공 명령어 관리

이전에 성공했던 SSH/mysql 명령어를 재사용 시 실패하는 경우가 있다.
검증된 명령어는 experience에 기록하고, 실패 시 기록된 명령어를 우선 참조한다.

→ See etap-build-deploy/SKILL.md § "검증된 명령어 참조"

## 화면 변화 없는 서비스 대응 (Gemini 등)

민감정보 입력 후 화면에 변화가 없는 서비스에서 Cowork가 작업 완료를 판단 못하는 문제.

```
대응 전략 (우선순위):
  1. 민감정보 입력+전송 직후 → DevTools Console 즉시 확인
  2. etap 로그로 동작 확인 (dev PC에서 SSH로 실시간 tail)
  3. etap.log를 Git 저장소의 artifacts/에 두어 test PC에서도 확인 가능하도록 조치
```

## test PC 스킬 품질 검증 — Phase 3 전 필수

test PC 스킬이 check-warning을 실제로 수행하지 않고 이전 결과를 재활용하는
문제가 발생한 적이 있다. Phase 3 batch 테스트 전에 반드시 단건 검증을 수행한다.

```
검증 방법:
  1. DONE 서비스(ChatGPT 등)로 check-warning 요청 전송
  2. result의 스크린샷 타임스탬프가 현재 시각과 일치하는지 확인
  3. actual_test_performed: true인지 확인
  4. 검증 실패 시 batch 테스트 진행하지 않음
```

## DB 패턴 변경 후 검증 절차

DB에 서비스 패턴을 추가/수정한 후, 실제로 detect가 동작하는지 4단계로 검증한다.

```
1. mysql UPDATE (test 서버 경유)
2. etapcomm ai_prompt_filter.reload_services
3. etap 로그에서 detect_and_mark grep
4. detect 성공 확인 → check-warning 진행
```

reload_services 없이 check-warning을 보내면 이전 패턴으로 동작한다.
