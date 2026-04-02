# Warning Pipeline — Service Status

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | Done | DONE | 2026-03-17 | Strategy C (HTTP/1.1), SSE warning |
| Claude | claude | Done | DONE | 2026-03-18 | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | perplexity | Done | DONE | 2026-03-17 | SSE stream warning |
| Gemini | gemini3 | 3 | NEEDS_MANUAL_ACTION | 2026-03-26 | DPDK IPv6 broken. TLS interception 중단. 인프라 수정 필요 |
| Grok | grok | 3 | WAITING_RESULT | 2026-03-26 | check-warning 결과 대기 중 (task #195) |
| Notion AI | notion | 3 | WAITING_RESULT | 2026-03-26 | check-warning 결과 대기 중 (task #198) |
| Genspark | genspark | 3 | WARNING_SHOWN_ARTIFACT_ISSUE | 2026-03-26 | 경고 표시 성공, network error artifact 잔존 |
| GitHub Copilot | github_copilot | 3 | BLOCKED_ONLY | 2026-03-27 | 422+JSON 전달 성공, 프론트엔드가 catch→generic error 표시. 커스텀 경고 불가 (Build #21) |
| Gamma | gamma | 3 | BLOCKED_ONLY | 2026-03-27 | 422 전달 성공, 프론트엔드가 fallback outline 생성. 커스텀 경고 불가 (Build #21) |
| M365 Copilot | m365_copilot | 3 | EXCLUDED | 2026-03-26 | 자동화 불가 + API endpoint 불확실. 수동 HAR 필요 |
## 서비스 우선순위 (난이도 기준)

한 번에 한 서비스만 작업한다. 난이도가 낮을수록 먼저 작업한다.
3/25 회고에서 3개 서비스 동시 진행으로 21테스트 전패한 경험에 의한 전략이다.

| 우선순위 | 서비스 | 현재 상태 | 난이도 | 근거 |
|---------|--------|----------|--------|------|
| 1 | Gemini | NEEDS_MANUAL_ACTION | 낮음 | DPDK IPv6 인프라 수정 후 check-warning만 하면 됨 |
| 2 | Grok | WAITING_RESULT | 낮음 | check-warning 결과 대기 중 |
| 3 | Notion AI | WAITING_RESULT | 낮음 | check-warning 결과 대기 중 |
| 4 | Genspark | WARNING_SHOWN_ARTIFACT_ISSUE | 중간 | network error artifact 해결 필요 |
| 5 | GitHub Copilot | BLOCKED_ONLY | 완료 | 차단 동작, 커스텀 경고 불가 (프론트엔드 fallback). 새 방식 확보 시 재시도 |
| 6 | Gamma | BLOCKED_ONLY | 완료 | 차단 동작, 커스텀 경고 불가 (프론트엔드 fallback). 새 방식 확보 시 재시도 |
| 7 | M365 Copilot | EXCLUDED | 매우 높음 | 자동화 불가, 수동 테스트 필요 |

**상태 설명:**
- BLOCKED_ONLY: 차단은 동작하지만 커스텀 경고 표시가 현재 기술로 불가능. 새로운 전달 방식 확보 시 재시도.

**난이도 판단 기준:**
- 낮음: DB+코드 완료, check-warning 테스트만 남음
- 중간: 부분 성공, 부수적 이슈 해결 필요
- 높음: 다수 실패 이력, 근본 접근법 재검토 필요
- 매우 높음: 자동화 불가 또는 구조적 제약
- 완료: DONE 또는 BLOCKED_ONLY (현재 가능한 범위에서 작업 종결)

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
- Gemini: Google IPv6 트래픽이 DPDK에 캡처되지 않음 (인프라 수정 필요)

## Note (2026-03-26)
- DB 인증 변경: `sudo mysql` (no password) — 기존 `root -pPlantynet1!` 대신
- test PC 활성 상태이나 check-warning 작업이 test-pc-worker에서 실행되지 않는 문제 확인됨