# Skill Update 지시사항 — 2026-03-20

## 우선순위 1: test-pc-worker 스킬 — check-warning 실행 로직 수정

### 문제
check-warning 명령 수신 시 실제 브라우저 테스트를 하지 않고 이전 run-scenario 결과를 재활용하여 보고.
critical_instruction, test_procedure 필드를 추가해도 무시됨.

### 필요 수정
check-warning 명령 처리 시:
1. 반드시 새로 Chrome 열기 (Start-Process chrome '{url}')
2. 페이지 로딩 대기
3. 입력창에 프롬프트 텍스트 입력 (SendKeys / clipboard paste)
4. 전송 (Enter)
5. 5초 대기
6. 스크린샷 캡처
7. 경고 메시지 표시 여부 판별
8. 결과 JSON에 실제 관찰 내용 기록

절대 금지: 이전 요청(run-scenario 등)의 결과를 참조하여 보고

### 추가
result JSON에 "actual_test_performed": true/false 플래그 추가

---

## 우선순위 2: test-pc-worker — M365 Copilot React 입력 대응

### 문제
contenteditable div가 SendKeys/clipboard paste/JS injection 모두 거부. 3회 실패.

### 수정 방안
- CDP(Chrome DevTools Protocol) --remote-debugging-port=9222 활용
- 또는 서비스별 입력 전략 분기 추가
- 최후 수단: "수동 입력 필요" 상태 보고

---

## 우선순위 3: genai-warning-pipeline — Service Status 업데이트

SKILL.md의 Service Status 테이블 업데이트:
- Gemini: Phase 3 ⚠️, DB 패턴 수정 완료, detect 성공, 차단 테스트 미수행
- Grok: Phase 3 ⚠️, DB OK, 코드 완료
- GitHub Copilot: Phase 3 ⚠️, DB 수정 완료(api.individual.githubcopilot.com)
- Gamma: Phase 3 ⚠️, DB 수정 완료(api.gamma.app)
- M365 Copilot: Phase 3 ❌, substrate.office.com, 자동화 불가
- Notion AI: Phase 3 ⚠️, 신규 DB+코드 완료(www.notion.so/api/v3/)

---

## 우선순위 4: genai-warning-pipeline — 운영 교훈 추가

### test PC 스킬 품질이 작업 병목
Phase 3 전에 test PC 스킬의 check-warning 동작을 단건 검증 후 진행.
검증 방법: DONE 서비스(ChatGPT)로 check-warning → 스크린샷 타임스탬프 확인.

### DB 패턴 변경 후 검증 절차
1. mysql UPDATE → 2. reload_services → 3. etap 로그 grep detect → 4. detect 확인
예시: gemini3 → signaler-pa.clients6.google.com detect 성공 ✅

---

## 우선순위 5: apf-warning-design — design docs 추가

/mnt/cowork/warning-pipeline/design-docs/ 에 생성된 6개 파일을 스킬 디렉토리로 복사:
gemini_design.md, grok_design.md, github_copilot_design.md,
gamma_design.md, m365_copilot_design.md, notion_design.md

---

## 우선순위 6: etap-build-deploy — 검증된 명령어 추가

```bash
# DB 패턴 업데이트 (2026-03-20 검증)
ssh -p 12222 solution@218.232.120.58 "mysql -h ogsvm -u root -pPlantynet1! etap -e \"UPDATE ...\""

# 서비스 리로드
ssh -p 12222 solution@218.232.120.58 'etapcomm ai_prompt_filter.reload_services'

# detect 확인
ssh -p 12222 solution@218.232.120.58 'tail -50 /var/log/etap.log | grep detect_and_mark'
```
