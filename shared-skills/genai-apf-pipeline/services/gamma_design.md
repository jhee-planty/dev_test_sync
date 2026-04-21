## Gamma — Warning Design

> **⚠️ STALE — PENDING_INFRA (2026-04-14 15:20, post-#450).**
> Three-cycle investigation of gamma blank-page failure concluded: **the cause is outside APF's observable code path.** Both the cycle 9 TLS-cert theory and the cycle 10 crt_manager RSA-forcing theory are REFUTED by the #450 HAR data.
>
> **What we know (from #450 HAR, 69 entries):**
> - 8 requests succeeded (status 200), including 3 to gamma.app itself: `/create/generate` (42KB HTML), `/manifest.json`, `/icons/pwa-icon-192x192.png`.
> - Two fresh TLS handshakes to gamma.app completed cleanly in the same page load → TLS interception works, `SetCertificate failed` is NOT the cause.
> - 61 requests to `gamma.app/_next/static/chunks/*.{js,css}?dpl=…` stalled 30s then failed with `status=0, dns/connect/ssl=-1, blocked≈30000ms` — Chrome's "connection pool could not satisfy request" state, not a server response.
> - `/manifest.json` succeeded ON THE SAME H2 connection while 61 /_next/static/* requests were mid-stall, proving the connection is healthy for some paths but not others.
>
> **What we verified (from DB + source):**
> - `ai_prompt_services` has no rule whose domain_patterns matches host `gamma.app`. The gamma row is `domain_patterns=ai.api.gamma.app` (exact match per `domain_matcher::match` at `ai_prompt_filter_db_config_loader.cpp:72-124`).
> - APF's service dispatcher should therefore ignore all `gamma.app` requests and leave the H2 stream untouched. APF cannot be the direct cause of the stalls.
>
> **What we couldn't verify (running-binary drift):**
> - The production etap binary on the test server emits `[APF] Page load request (Accept: text/html)` from `ai_prompt_filter.cpp:697`. That string does not exist in ANY branch of this worktree (`git log --all -S` returns zero hits). The running binary is a different source tree than what we've been code-reading. Our code-reading cannot predict its behavior.
> - etap.log on the test server stopped appending at 14:59:28.860 KST. Current time 15:20+. The process is alive but the logger is silent through both #449 and #450 windows. L2 SSH monitoring is currently a blind spot.
>
> **Candidate causes that remain open (not ruleable out from dev PC alone):**
> 1. Running binary has hardcoded /_next/static handling not in our worktree.
> 2. visible_tls layer has a concurrent-stream or connection-pool quota that stalls bursts of 61 parallel static fetches.
> 3. Cloudflare-side rate limit or WAF rule firing against the TLS-intercepted client fingerprint.
> 4. etap.log silence hints at a process-internal issue (logger stuck, or etap no longer in data path) that also explains why we can't observe the failure from L2.
>
> **Status: PENDING_INFRA.** gamma is not diagnosable with current dev-side tools and without touching production artifacts. Resume criteria: (a) user or infra engineer investigates production binary source + restarts etap to clear logger state, (b) after restart, re-run a minimal HAR probe to see if the stall pattern reproduces, (c) if it does, escalate to a Cloudflare/TLS fingerprint investigation.
>
> Full forensic record: `local_archive/gamma_blank_page_analysis_2026-04-14.md` (cycles 9/10/11 sections).
> #158's "SendKeys can't paste into textarea" was retroactively the same blank-page failure, mis-diagnosed.

### Strategy
- Pattern: H2_DATA_WARNING (attempted) → **NEEDS_ALTERNATIVE**
- HTTP/2 strategy: B (keep-alive, is_http2=2)
- Based on: Gamma uses HTTP/2 streaming. H2 DATA frame delivery 실패.

### Response Specification
- API: ai.api.gamma.app, path=/
- is_http2: 2 (keep-alive)

### Current State: NEEDS_ALTERNATIVE
H2 DATA frame delivery 실패. 7빌드 실패 이력.

**대안 접근법** (2026-04-10, apf-technical-limitations.md §5):
1. EventSource 호환 에러 이벤트 전달

### Known Constraints
- H2 DATA frame이 클라이언트에 도달하지 않음
- cert error 가능성
- 7빌드 실패 이력

### 새로운 접근법 (Phase 2 재설계)
1. **is_http2 변경**: 2→1 또는 0으로 변경하여 다른 전송 전략 시도
2. **에러 응답**: HTTP 에러 코드로 프론트엔드 에러 UI 활용
3. **block page**: ai.api.gamma.app 차단 + HTML 경고 페이지

### Test Criteria
- [ ] 차단 동작 확인
- [ ] H2 DATA delivery 성공 여부 확인
- [ ] 경고 문구 표시 여부

### Relationship to Existing Code
- Existing generator: 없음 확인 필요 (register_block_response_generators 검색)
- is_http2 value: 2
- DB: ai.api.gamma.app, path=/

### Notes
- 7빌드 실패 + cert error 이력. 근본적 전송 계층 문제 가능성.
