# ECH (Encrypted Client Hello) Analysis — duck.ai VT Interception Failure

## Problem

Test #307: DuckDuckGo AI Chat (duck.ai) APF warning template deployed correctly, but VT never intercepted the connection. APF saw zero log entries for duck.ai. The request went directly to the server without MITM.

## Root Cause Hypothesis: ECH

**Encrypted Client Hello (ECH)** encrypts the SNI (Server Name Indication) in the TLS ClientHello, preventing MITM proxies from identifying the target domain.

### Evidence

1. **Cloudflare activated ECH globally in late 2024** — any site on Cloudflare has ECH enabled by default
2. **duck.ai is likely on Cloudflare** — DuckDuckGo uses Cloudflare infrastructure
3. **59% of browsers support ECH** — Chrome, Edge, Firefox, Safari all support it
4. **VT doesn't handle ECH** — Etap VT was designed pre-ECH
5. **Test #307 shows zero VT log entries** — consistent with ECH bypass (VT can't even see the domain name)

### How ECH Breaks MITM

1. Browser resolves duck.ai DNS → gets HTTPS record with ECH public key
2. Browser sends ClientHello with encrypted inner SNI (`duck.ai`) and outer SNI (`cloudflare-ech.com`)
3. VT intercepts ClientHello → sees outer SNI `cloudflare-ech.com`, not `duck.ai`
4. VT creates fake certificate for `cloudflare-ech.com` or fails TLS handshake
5. Browser detects ECH failure → either shows error or retries
6. VT auto-bypass triggers → connection goes through without MITM

## Verification Plan (Test #308)

1. Check `chrome://flags/#encrypted-client-hello` on test PC
2. Disable ECH in Chrome
3. Retest duck.ai → if APF intercepts, ECH is confirmed as cause

## Fix Options

### Option 1: Chrome Flag (Immediate, Client-side)
- Disable ECH in Chrome via `chrome://flags/#encrypted-client-hello`
- **Pros**: Immediate fix, no code changes
- **Cons**: Not scalable for enterprise deployment, per-browser config

### Option 2: DNS-level ECH Key Blocking (Network-level)
- Block HTTPS/SVCB DNS records that contain ECH keys
- Without ECH keys, browser falls back to standard TLS (non-ECH)
- **Pros**: Network-level fix, affects all clients, no VT code changes
- **Cons**: Requires DNS infrastructure changes (Etap DNS module or external DNS)
- **Implementation**: Configure DNS resolver to strip HTTPS records or return NXDOMAIN for HTTPS type queries

### Option 3: VT ClientHello ECH Stripping (VT Code Change)
- VT intercepts ClientHello and strips the ECH extension before forwarding
- Server sees no ECH → negotiates standard TLS with visible SNI
- **Pros**: Transparent to clients, handles all ECH-capable sites
- **Cons**: Requires VT C++ code changes, ~200-400 LOC
- **Implementation**: Parse ClientHello extensions, remove ECH (type 0xfe0d), recalculate lengths

### Option 4: Bridge-level ECH Blocking (DPDK/NIC level)
- Block or modify TLS ClientHello packets with ECH extension at bridge layer
- **Pros**: Hardware-level, fast
- **Cons**: Complex, may break non-MITM connections

## Recommendation

**Short-term**: Option 1 (Chrome flag) for testing, verify ECH is the cause
**Medium-term**: Option 2 (DNS-level) — least code change, broadest coverage
**Long-term**: Option 3 (VT ECH stripping) — most robust MITM solution

## Affected Services

Any service using Cloudflare with ECH may be affected:
- **duck.ai** (confirmed VT MITM failure, #307)
- **chat.deepseek.com** (Cloudflare confirmed — untested with APF yet)
- **claude.ai** (Cloudflare — currently working, but may break if ECH activates for this zone)
- **chatgpt.com** (Cloudflare — currently working, but may break if ECH activates)
- Other Cloudflare-hosted AI services

Note: ChatGPT and Claude may still work because:
1. ECH rollout is per-zone — not all Cloudflare zones have ECH active simultaneously
2. The test PC Chrome may have cached non-ECH sessions for those domains
3. ECH keys are distributed via HTTPS DNS records — if DNS resolver doesn't return them, browser uses standard TLS
4. VT's auto-bypass list is persistent — once bypassed, a domain stays bypassed until TTL expires

### Risk Assessment
- **Immediate**: duck.ai blocked from VT MITM
- **Near-term**: chat.deepseek.com may face same issue when APF service is registered and deployed
- **Long-term**: ALL Cloudflare services will eventually have ECH → existing ChatGPT/Claude blocks may break

## Timeline

- 2026-04-09 11:45 — Test #307 failed (VT not intercepting duck.ai)
- 2026-04-09 12:10 — Test #308 created (ECH diagnostic)
- 2026-04-09 12:20 — ECH analysis document created, VT source code reviewed
- 2026-04-09 12:30 — Confirmed chat.deepseek.com also on Cloudflare
- Pending: #308 result to confirm ECH hypothesis
