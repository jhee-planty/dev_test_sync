# Warning Pipeline — Service Status

| Service | service_id | Phase | Status | Last updated | Notes |
|---------|-----------|-------|--------|-------------|-------|
| ChatGPT | chatgpt | 3 | VERIFIED | 2026-04-02 | ✅ 경고 표시 성공. Strategy C, SSE_STREAM_WARNING |
| Claude | claude | 3 | VERIFIED | 2026-04-02 | ✅ 경고 표시 성공. Strategy A, SSE_STREAM_WARNING |
| Genspark | genspark | 3 | VERIFIED | 2026-04-02 | ✅ 경고 표시 성공. Strategy B, SSE_STREAM_WARNING |
| Notion AI | notion | 3 | BLOCKED_SILENT_RESET | 2026-04-02 | ⚠️ 차단 O, 경고 미표시. 채팅 리셋됨. NDJSON 응답 파싱 실패 추정 |
| GitHub Copilot | github_copilot | 3 | PARTIAL_WARNING | 2026-04-02 | ⚠️ 차단 O, GitHub 403 에러 형식으로 표시. APF 경고 텍스트 아님 |
| Gemini | gemini3 | 3 | TESTING | 2026-04-03 | 🔄 BLOCKED_ONLY 철회 → code_bug(hold flag) 수정 후 B14 테스트 대기. 유효 카운트 2/7 |
| M365 Copilot | m365_copilot | 3 | BLOCK_FAILED | 2026-04-02 | ❌ 차단 실패. 정상 AI 응답 반환. DB 등록 또는 패턴 매칭 문제 |
| Grok | grok | 2 | BLOCKED_ONLY | 2026-04-02 | NDJSON 프로토콜 한계. B1-B7 시도 실패. 경고 전달 불가 |
| Perplexity | perplexity | 2 | BLOCKED_ONLY | 2026-04-02 | Strategy D, 블록 가능. 페이로드 검증으로 경고 주입 불가 |
| Gamma | gamma | 1 | BLOCKED_ONLY | 2026-04-02 | 프레젠테이션 생성 도구. 자동 입력 불가 |


## Phase 3 테스트 결과 요약 (2026-04-02)

| 서비스 | 결과 | 경고 표시 | 차단 | 비고 |
|--------|------|----------|------|------|
| ChatGPT | ✅ VERIFIED | O | O | 텍스트 차이 있으나 경고 인지 가능 |
| Claude | ✅ VERIFIED | O | O | 텍스트 차이 있으나 경고 인지 가능 |
| Genspark | ✅ VERIFIED | O | O | 슈퍼 에이전트 모드에서 정상 표시 |
| Notion AI | ⚠️ BLOCKED_SILENT | X | O | 차단 성공, 경고 미표시 (채팅 리셋) |
| GitHub Copilot | ⚠️ PARTIAL | △ | O | GitHub 403 에러로 표시, APF 텍스트 아님 |
| Gemini | 🔄 TESTING | △ | X | hold flag 버그 수정 후 B14 대기 (유효 2/7) |
| M365 Copilot | ❌ FAILED | X | X | 차단 미작동, 정상 응답 반환 |

**성공: 3개** (ChatGPT, Claude, Genspark)
**부분 성공: 2개** (Notion AI — 차단만, GitHub Copilot — 차단+403)
**재시도 대기: 1개** (Gemini — hold flag 버그 수정 후 B14)
**실패: 1개** (M365 Copilot — 차단 자체 미작동)
**BLOCKED_ONLY: 3개** (Grok, Perplexity, Gamma)

---

## 다음 단계

1. **Gemini**: hold flag 버그(session-level → VTS-level) 수정 후 B14 빌드+테스트. code_bug 면제 적용 (유효 2/7).
2. **M365 Copilot**: DB 등록 상태 확인. copilot.microsoft.com의 API 엔드포인트가 DB에 미등록일 가능성.
3. **Notion AI**: NDJSON 응답 포맷 재검토. 프론트엔드가 응답을 파싱하지 못해 silent reset 발생.
4. **GitHub Copilot**: 경고 텍스트를 한글로 변경 필요 (현재 영문 403 에러 표시).

---

## Experience Files

| Service | Experience files |
|---------|-----------------|
| ChatGPT | `apf-warning-design/services/chatgpt_design.md` |
| Claude | `apf-warning-design/services/claude_design.md` |
| Perplexity | `apf-warning-design/services/perplexity_design.md` |
| Genspark | `apf-warning-design/services/genspark_design.md` |
| Gemini | `apf-warning-design/services/gemini_design.md` |
| Grok | `apf-warning-design/services/grok_design.md` |
| GitHub Copilot | `apf-warning-design/services/github_copilot_design.md` |
| Gamma | `apf-warning-design/services/gamma_design.md` |
| M365 Copilot | `apf-warning-design/services/m365_copilot_design.md` |
| Notion AI | `apf-warning-design/services/notion_design.md` |
