# Warning Pipeline — Service Status

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | Done | DONE | 2026-03-17 | Strategy C (HTTP/1.1), SSE warning |
| Claude | claude | Done | DONE | 2026-03-18 | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | perplexity | Done | DONE | 2026-03-17 | SSE stream warning |
| Genspark | genspark | 3 | TESTING | 2026-03-20 | Strategy B, 경고 표시되나 network error artifact 잔존 |
| Gemini | gemini3 | 3 | RE-TESTING | 2026-03-23 | DB 수정 완료, systemctl 재시작 후 re-test 138 대기 |
| Grok | grok | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 (입력 거부, 인증 필요, cert mismatch). 수동 테스트 필요 |
| GitHub Copilot | github_copilot | 3 | TEST_FAIL | 2026-03-23 | blocked=true, warning 미표시 (SSE stuck). Re-test 140 대기 |
| Gamma | gamma | 3 | PENDING | 2026-03-23 | 134 결과 미도착. cert error 가능성 |
| M365 Copilot | m365_copilot | 3 | EXCLUDED | 2026-03-23 | 자동화 불가 + API endpoint 불확실. 수동 HAR 필요 |
| Notion AI | notion | 3 | TEST_FAIL | 2026-03-23 | 미차단. detect 0건. WebSocket 우회 또는 API endpoint 불일치. Re-test 141 대기 |

## 서비스 우선순위 (난이도 기준)

한 번에 한 서비스만 작업한다. 난이도가 낮을수록 먼저 작업한다.
3/25 회고에서 3개 서비스 동시 진행으로 21테스트 전패한 경험에 의한 전략이다.

| 우선순위 | 서비스 | 현재 상태 | 난이도 | 근거 |
|---------|--------|----------|--------|------|
| 1 | Gemini | DB+detect 완료 | 낮음 | check-warning만 하면 됨, Strategy D |
| 2 | Grok | DB+코드 완료 | 낮음 | check-warning만 하면 됨 |
| 3 | Notion AI | DB+코드 완료 | 낮음 | check-warning만 하면 됨 |
| 4 | Genspark | body 전달 성공 | 중간 | network error artifact 해결 필요 |
| 5 | GitHub Copilot | DB 완료 | 높음 | 8회 연속 실패 이력, 접근법 재검토 필요 |
| 6 | Gamma | DB 완료 | 높음 | 7빌드 실패, UI 렌더링 이슈 |
| 7 | M365 Copilot | Phase 3 미진입 | 매우 높음 | 자동화 불가, 수동 테스트 필요 |

**난이도 판단 기준:**
- 낮음: DB+코드 완료, check-warning 테스트만 남음
- 중간: 부분 성공, 부수적 이슈 해결 필요
- 높음: 다수 실패 이력, 근본 접근법 재검토 필요
- 매우 높음: 자동화 불가 또는 구조적 제약

갱신 시점: 서비스 완료 시, 또는 난이도 재평가 시.

---

## Experience Files

서비스별 design/impl 파일 경로. 새 서비스 작업 시 유사 전략의 기존 경험을 참조한다.

| Service | Experience files |
|---------|-----------------|
| ChatGPT | `apf-warning-design/services/chatgpt_design.md`, `apf-warning-impl/services/chatgpt_impl.md` |
| Claude | `apf-warning-impl/services/claude_impl.md` |
| Perplexity | `apf-warning-design/services/perplexity_design.md`, `apf-warning-impl/services/perplexity_impl.md` |
| Genspark | `apf-warning-impl/services/genspark_impl.md` |
| Gemini | `apf-warning-design/services/gemini_design.md`, `apf-warning-impl/services/gemini_impl.md` |
| Grok | `apf-warning-design/services/grok_design.md` |
| GitHub Copilot | `apf-warning-design/services/github-copilot_design.md` |
| Gamma | `apf-warning-design/services/gamma_design.md` |
| M365 Copilot | `apf-warning-design/services/m365-copilot_design.md` |
| Notion AI | `apf-warning-design/services/notion_design.md` |

---

## Infrastructure Note (2026-03-23)
- 08:20 runetap 재시작 → DPDK init 실패 → 전체 TLS 인터셉션 중단
- 10:05 systemctl restart → DPDK 정상 초기화, detect 복구 (10:07:09)
- 138-141 재테스트 진행 중
