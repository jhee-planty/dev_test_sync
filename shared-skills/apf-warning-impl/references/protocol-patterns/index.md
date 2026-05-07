# Protocol Pattern References (57차 신설 — α+β architectural shift)

**Purpose**: AI service 의 architectural specificity 를 protocol pattern 단위로 generalize. service-specific detail (endpoint / auth / SPA bundle) 은 LLM 이 runtime 에 발견 (HAR / production log / sub-agent), 본 reference 는 **pattern-level mechanism + common pitfall** 만 제공.

**Design intent** (사용자 directive 57차):
- Skill = 일반 framework + protocol pattern reference
- Service-specific knowledge = operational state (`apf-operation/services/{service}/`), skill 외부
- LLM context window 부담 ↓

**Pattern list** (7 patterns, 47-56차 incident evidence 기반):

| # | Pattern | File | Services 적용 사례 |
|---|---|---|---|
| 1 | **Server-Sent Events (SSE)** | [sse.md](sse.md) | perplexity (`/rest/sse/perplexity_ask`), mistral (일부 endpoints) |
| 2 | **WebSocket (RFC 6455)** | [websocket.md](websocket.md) | character (add_turn), kimi (Connect-RPC) |
| 3 | **tRPC + superJSON** | [trpc.md](trpc.md) | mistral (`/api/trpc/message.newChat`) |
| 4 | **signalR (Microsoft Chathub)** | [signalr.md](signalr.md) | copilot (m365 Chathub) |
| 5 | **NDJSON multi-stage** | [ndjson.md](ndjson.md) | notion (multi-tool-call sequence + zstd) |
| 6 | **HTTP polling (request/response)** | [http-polling.md](http-polling.md) | gamma, simple chat services |
| 7 | **SPA hydration / hardening** | [spa-hydration.md](spa-hydration.md) | gemini3 (Quill + Trusted Types CSP), 다수 frontend hardened services |

---

## Each pattern reference 의 standard structure

각 protocol pattern reference 는 다음 sections 포함:

1. **Mechanism** — 해당 protocol 의 frame / chunk / packet 구조
2. **Engine emit** — APF engine 의 어떤 hook 이 fire (e.g., `[APF:block_response]`, on_http2_response_data, on_upgraded_data)
3. **Envelope schema requirements** — frontend SPA 가 accept 하는 schema 의 일반 structure (common fields, validation rules)
4. **Common pitfalls** — 해당 protocol 의 typical 실패 패턴 (e.g., wrong endpoint, schema mismatch, bundle hardening)
5. **Verify path** — engine fire 확인 방법 (production log query) + UI render 확인 방법 (test PC verdict)
6. **Cross-reference** — 비슷한 service 의 operational state pointer (apf-operation/services/{service}/)

---

## Skill SKILL.md integration

각 service 의 next_action 진행 시:
1. service 의 protocol pattern 식별 (e.g., perplexity = SSE)
2. 해당 pattern reference + service operational state 함께 read
3. service-specific detail (endpoint, schema delta, auth) 은 operational state 에서 read
4. Pattern reference 가 generalize 가능한 mechanism + pitfall 제공

**Anti-pattern (D9 Stage 5 호환)**: pattern reference 만 read 하고 service-specific operational state ignore = Performative Compliance. 양쪽 모두 read 의무.

---

## Migration status (57차)

- ✅ Step 1 (β): 본 index + 7 placeholder reference 신설
- ✅ Step 2 (α 자율): SKILL.md 의 services/*.md 의미 재정의 (operational state, skill 외부)
- ⏸ Step 3 (α 사용자 영역): 실제 file 이동 (`shared-skills/{skill}/services/*.md` → `apf-operation/services/{service}/`) — 다른 session 영향, 사용자 confirm 후
- ⏸ Step 4: 56차 schema references pointer update (Step 3 후 자동)

---

## Reference 의 cumulative substance

각 placeholder reference 는 47-56차 incident evidence 기반 minimal substance 시작. **Substance 는 cumulative** — 매 incident / discovery 시 add (D27 positive procedure 적용).

본 placeholder 는 fast-path scaffold — actual mechanism detail 은 다음 incidents 시 cumulative codify.
