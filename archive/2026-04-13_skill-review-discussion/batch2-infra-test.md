# SKILL.md Analysis: Infrastructure & Test Skills (Batch 2)

**Analysis Date:** 2026-04-13  
**Session:** Structured Review of Cross-Skill Dependencies and Integration Points

---

## 1. etap-build-deploy

### Name & Purpose
**EtapV3 build and test server deployment skill.** Syncs locally modified source to the compile server, builds with ninja, and deploys to the test server. Covers the entire build-deploy-verify cycle, including incremental rebuilds and error handling. Used for all EtapV3 module changes (APF, VT, etc.).

### Metadata
- **Line Count:** 509 lines
- **Language Mixed:** Korean (주석, 섹션 헤더) + English (명령어, 경로)
- **Format:** Markdown with embedded bash code blocks

### Key Sections
| Section | Lines | Purpose |
|---------|-------|---------|
| Frontmatter (YAML) | 1-5 | Skill metadata & trigger conditions |
| 터미널 사용 규칙 (Terminal Rules) | 20-39 | Single-terminal execution principle |
| SSH 접근 규칙 (SSH Access Rules) | 41-61 | Cowork vs Claude Code tool selection |
| Server Info | 63-72 | Compile/test server IPs and ports |
| Paths | 74-90 | Path mappings (local, compile, deploy) |
| 작업 시작 전 스킬 로드 확인 | 92-99 | Session context recovery |
| 스크립트 사용법 (권장) | 101-134 | Script-driven workflow (preferred) |
| Pre-flight Checklist | 156-180 | 5 manual verification steps |
| Step 1 — Source Sync | 184-209 | scp: local → compile server |
| Step 2 — Build + Install | 212-241 | ninja on compile server |
| Step 3 — Deploy | 244-276 | scp: compile → local → test |
| Step 3.5 — Deploy Safety Check | 279-305 | **MANDATORY tarball validation** |
| Step 4 — Install & Restart | 308-345 | tar extract + systemctl restart |
| Post-Deploy 배포 검증 게이트 | 347-375 | Binary timestamp verification |
| Incremental Rebuild | 378-410 | Partial fix workflow |
| Error Handling | 413-463 | SSH/scp/build failures + symlink recovery |
| 검증 된 명령어 참조 | 467-501 | Known-good command history (2026-03-20, 2026-04-07) |
| Related Skills | 504-509 | genai-warning-pipeline, apf-warning-impl |

### Cross-References & Dependencies
**Skills Referenced:**
- `genai-warning-pipeline` (Phase 4: release build) — Uses this skill for deployment
- `apf-warning-impl` (Phase 3-4) — Triggers test builds via this skill
- `_backup_20260317/genai-apf-pipeline` — Archived prior pipeline

**Files & Repositories Referenced:**
- `dev_test_sync/scripts/mac/etap-preflight.sh`, `etap-build-deploy.sh`
- `dev_test_sync/scripts/lib/common.sh` (shared functions)
- `dev_test_sync/scripts/lib/output-format.md` (JSONL output spec)
- `/home/solution/source_for_test/EtapV3/` (compile server source)
- `~/Documents/workspace/Officeguard/EtapV3/` (local source)

### Trigger Conditions
**Primary Triggers:** "build", "deploy", "ninja", "scp to server", "send to test"  
**Extended Triggers:** "building", "deploying", "compiling", "pushing code to test server"  
**Short Requests:** "build it", "deploy", "빌드"

### Recent Changes & Dates
- **2026-04-07:** REMOTE_SRC path confirmed in scp failure section (line 426)
- **2026-03-27 Build #21:** Deployment verification gate added due to binary non-deployment incident
- **2026-03-20:** Verified commands added: MySQL DB access, service reload, detect log check
- **2026-04-06:** System symlink recovery procedure added (lines 432-463) — validated in production incident
- **2026-03-17:** Pipeline backup created (`_backup_20260317/`)

### Potential Issues

#### 1. **Outdated/Suspicious References**
- **Line 426:** Comment says "confirmed 2026-04-07" but this is only 6 days in the future from analysis date (2026-04-13). Verify if this is a logging/timestamp error.
- **Line 374:** Reference to `apf-warning-impl/SKILL.md § Step 5` without full path qualification — assumes skill is available at runtime.

#### 2. **Broken Cross-References**
- **Line 507-508:** References "genai-warning-pipeline" and "apf-warning-impl" but these are listed as related skills, not as shareable links. If these skills were moved or renamed, the references break.
- **Line 508:** "genai-apf-pipeline" marked as "backed up" but no forward migration guide provided.

#### 3. **Inconsistencies Between Description & Content**
- **Frontmatter (lines 3-4):** Claims "not just APF" but all recent examples (lines 374, 506) are APF-specific. Build-deploy itself is module-agnostic, but integration is APF-heavy.
- **SSH Access Rules (lines 43-59):** Diagram suggests Cowork uses "desktop-commander 경유" (via desktop-commander) but desktop-commander is an MCP for file I/O, not SSH execution. SSH from Cowork should use `mcp__desktop-commander__start_process`. Description may be imprecise.

#### 4. **Missing Information/Gaps**
- **Line 101-108:** Script location path uses `dev_test_sync/scripts/mac/` but no instructions on how to clone/install `dev_test_sync` repo locally.
- **Lines 224-232:** Build success indicators show package creation, but **no guidance on what to do if ninja incremental build produces no .tgz file** (e.g., if source sync was incomplete).
- **Line 279-305:** Deploy Safety Check is marked "MANDATORY" but there's no fallback procedure if tarball is unsafe. Instruction says "stop extraction" but doesn't specify how to roll back or recover.

#### 5. **Overly Complex Instructions**
- **Lines 220-222:** `sudo ninja && sudo ninja install` are chained but the skill doesn't explain why both are needed in one command vs. separately. Adds cognitive load.
- **Lines 432-463:** System symlink recovery procedure is 29 lines for what amounts to 4 commands. Could be condensed with clearer structure.

#### 6. **Duplicate Content Across Skills**
- **Steps 1-4 in this skill vs. `etap-testbed` lines 137-166:** Both describe the same scp/ninja/tar workflow. The duplication is intentional (testbed uses on-server build), but the skill cross-reference is unclear.
  - **etap-testbed Step 1** says "기존 빌드 패키지 사용" (use existing package) OR "소스 변경 후 빌드 필요한 경우" (build after source change).
  - But **etap-build-deploy** always assumes source change → build. No clear marker on which skill to use when.

#### 7. **Unclear Error Recovery Paths**
- **Line 341:** If `tar xzf` fails with "Corrupted or missing package", instruction is "Re-run Step 3 deploy". But Step 3 operates on `etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz` which may already be corrupted. Should clarify: delete .tgz first? Rebuild? No guidance.

#### 8. **Terminal Management Rule Conflict**
- **Lines 20-39:** "Single terminal for all remote commands" rule. But **line 30 exception:** "로그 모니터링(tail -f)이 필요한 경우만 예외적으로 두 번째 터미널 허용" (second terminal allowed for log monitoring).
- **Implication:** If ninja build fails, developer might want to tail `/var/log/etap.log` while rebuilding. This conflicts with the "single terminal" rule. No explicit guidance on how to handle this.

#### 9. **Version/Configuration Drift Risk**
- **Line 96-98:** "서버 주소, 경로 매핑, 패키지 파일명 규칙 등을 기억에 의존하면 오래된 정보로 작업하게 된다" (relying on memory leads to stale info).
  - Yet the skill itself contains hardcoded paths (lines 75-89) that could become stale.
  - **Recommendation:** Move server IPs and paths to an external config file (e.g., `.env` or `servers.json`) referenced at runtime.

#### 10. **Package Versioning Ambiguity**
- **Lines 265-275:** Package naming convention uses `{YYMMDD}` (date). Same date, multiple builds → same filename → overwrites previous build.
  - Skill says "수동으로 백업한다" (manually backup) as workaround, but this is error-prone.
  - **Recommendation:** Add build sequence number (e.g., `etap-root-260319-01.sv.debug.x86_64.el.tgz`) or full timestamp.

---

## 2. etap-testbed

### Name & Purpose
**Etap module functional test guide for Dell testbed.** Provides the complete workflow for verifying Etap modules (VT, APF, bridging, NIC) on a closed 3-server testbed (Dell-1 ↔ Etap MITM bridge ↔ Dell-2). Covers HTTPS interception, keyword blocking, log verification, and troubleshooting.

### Metadata
- **Line Count:** 393 lines
- **Language Mixed:** Korean (헤더, 주석) + English (명령어, 테이블)
- **Format:** Markdown with embedded bash, SQL, etapcomm commands

### Key Sections
| Section | Lines | Purpose |
|---------|-------|---------|
| Frontmatter (YAML) | 1-18 | Skill metadata & trigger conditions |
| Purpose | 20-24 | High-level goal statement |
| 테스트 망 구성 (Network Topology) | 26-45 | 3-server setup (Dell-1, Dell-2, Etap) + comment about server info update locations |
| 경로 정보 (Path Info) | 80-105 | Build packages, source, config, binary, log paths |
| Pre-flight Checklist | 108-134 | 6 verification steps ([1/5] → [6/6]) |
| Step 1 — 배포 & 재시작 | 137-195 | Deploy package, restart service, handle module config changes, failure recovery |
| Step 2 — 모듈 상태 확인 (etapcomm) | 198-217 | Diagnostics: port_info, APF stats/config, keyword test, reload |
| Step 3 — HTTPS 테스트 (VT MITM) | 221-300 | HTTPS test via curl --resolve, VT prerequisites, packet capture with tshark |
| Step 4 — 검증 (Verification) | 304-334 | Log checks, verification checklist (etapd instance count, MITM issuer, block response, etc.) |
| Step 5 — 정리 (Cleanup) | 338-346 | Process cleanup, file recovery |
| 트러블슈팅 (Troubleshooting) | 350-356 | References external file `references/troubleshooting.md` |
| Incremental Fix | 359-371 | Partial fix workflow (source → scp → ninja → restart) |
| DB 참고 (DB Reference) | 375-379 | MySQL access, queries for APF service/keyword/block logs |
| 주의사항 (CAUTION) | 383-386 | SSH credentials included in skill — warn before sharing .skill package |
| Related Skills | 389-393 | etap-build-deploy, genai-apf-pipeline |

### Cross-References & Dependencies
**Skills Referenced:**
- `etap-build-deploy` — Invoked for source changes requiring build
- `genai-apf-pipeline` — APF code development pipeline

**External Files Referenced (via "See references/…" pattern):**
- `references/vt-test-guide.md` (lines 74, 223) — VT solo test procedures
- `references/etapcomm-commands.md` (lines 74, 200, 217) — Full etapcomm command reference
- `references/troubleshooting.md` (line 355) — Troubleshooting procedures
- `references/db-queries.md` (line 379) — Frequently used DB queries

**Database & Service Info Referenced:**
- `ai_prompt_filter_services` table (domain_patterns, service_name)
- `ai_prompt_services` table (not directly named but implied)
- `ai_prompt_block_log` table (INSERT records for blocked requests)
- DB host: `ogsvm = 172.30.10.72`

### Trigger Conditions
**Primary Triggers:** "테스트베드", "Dell 테스트", "테스트 망", "HTTPS 차단 테스트", "MITM 테스트", "모듈 테스트"  
**Extended:** "etapd 테스트", "etapcomm 테스트", "APF 테스트", "VT 테스트", "차단 테스트", "배포 후 테스트", "기능 검증", "통합 테스트", "브릿지 테스트", "NIC 테스트", "포트 상태", "module.xml", "모듈 활성화", "VT bypass 테스트"  
**Do NOT Trigger For:** 소스 코드 수정 (.cpp, .h), HAR analysis, DB schema design, build-only (→ etap-build-deploy), APF code dev (→ genai-apf-pipeline)

### Recent Changes & Dates
- **Line 74-76:** Explicit disclaimer added: testbed is for **module-level verification only**, not real-service integration. Real service (chatgpt.com, claude.ai) testing happens on test PC via `cowork-remote` (lines 76-77).
- **Line 133:** Pre-flight [6/6] added to confirm available compile directories (e.g., EtapV3_vt/) if main EtapV3 is in use.
- **Failure recovery table (lines 189-194):** Added "Active인데 ping 실패" case — directs to symlink recovery via troubleshooting.md.

### Potential Issues

#### 1. **Outdated References (Architectural Shift)**
- **Lines 74-77:** Skill now explicitly warns that **testbed ≠ real-service testing**. This is a recent architectural shift separating module testing (closed testbed) from integration testing (real services on test PC).
  - **Risk:** Old documentation or user habits might conflate the two. The skill guards against this, but it's worth noting that all prior APF tests on chatgpt.com/claude.ai were architecture violations.
  - **Implication:** If user says "test on chatgpt", this skill should redirect to `cowork-remote` (test PC).

#### 2. **Broken Cross-References**
- **Lines 74, 200, 217, 355, 379:** All reference `references/` subdirectory files (vt-test-guide.md, etapcomm-commands.md, troubleshooting.md, db-queries.md).
  - **Issue:** These files are not provided in this skill. Are they in the Git repo? Are they generated? If missing, the user will hit "file not found" errors.
  - **Recommendation:** Include all `references/` files in the skill distribution, or provide a fetch mechanism.

#### 3. **Inconsistencies Between Description & Content**
- **Frontmatter (lines 3-8):** Says "폐쇄 테스트 망" (closed test network) but lines 63-65 list SSH ports (10000, 12222). These are externally reachable, not "closed" in the strict sense. The network is closed **among the 3 servers**, but each server is SSH-accessible from outside.
  - **Clarity Issue:** Confusing terminology.

#### 4. **Missing Information/Gaps**
- **Lines 32-34:** Table shows Etap 서버 as "Xeon Silver 4208" with "브릿지 모드" (bridge mode) but no information on which interface pairs are used (e.g., si/so vs vi/vo). This is implicit in line 53 (`si/so(main) + vi/vo(sub)`) but buried in a topology diagram.
  - **Recommendation:** Add explicit NIC port mapping in the server table.
- **Lines 137-150:** "Step 1 — 배포 & 재시작" handles two cases: (a) use existing package, (b) rebuild after source change. But **if neither applies** (e.g., want to re-extract an existing package), the instructions are unclear.
  - **Gap:** No procedure for "reset config without changing source".
- **Lines 168-183:** module.xml editing shown via `sudo vi` but no guidance on what settings to change. User must know the XML structure in advance.
  - **Recommendation:** Provide example module.xml snippet for disabling VT or APF.

#### 5. **Overly Complex Instructions**
- **Lines 221-246:** VT MITM prerequisites table is good, but the description of "bypass 미해당" (not subject to bypass) is unclear. Is a server in `bypass_servers` table entry A, B, or C?
  - **Unclear:** What does "bypass 미해당" mean? That it's NOT in the bypass list? That it IS?
  - **Recommendation:** Use clearer language: "서버가 bypass_servers에 등록되지 않아야 함" (server must NOT be registered in bypass_servers).

#### 6. **Duplicate Content Across Skills**
- **Step 1 (lines 137-195) vs. etap-build-deploy Steps 1-4 (lines 184-345):**
  - etap-testbed Step 1a uses **existing package** (tar xzf). This mirrors etap-build-deploy Step 4 (extract on test server).
  - etap-testbed Step 1b does **scp + ninja + install**. This mirrors etap-build-deploy Steps 1-2 (but on-server).
  - **Duplication Severity:** Medium. Both need to exist, but users may not know which to follow when.
  - **Recommendation:** Add decision tree: "Do you have a recent .tgz package? → Use Step 1a. Did you just modify source? → Use Step 1b."

#### 7. **Error Recovery Gaps**
- **Line 194:** "Active인데 ping 실패 / TLS 미작동" case directs to troubleshooting.md § "runetap vs systemctl". But what if the user runs etapd directly (violating the "use systemctl" rule)? How do they know they made this mistake?
  - **Recommendation:** Add a quick check: `pgrep -c etapd` must equal 1. If > 1, that's the problem.

#### 8. **Security/Credentials Disclosure**
- **Lines 32-34, 384-386:** Skill contains SSH credentials (IPs, ports, usernames). Line 384-386 warns: "주의사항 — `.skill` 패키지 배포 시…접속 정보가 함께 배포됨에 유의한다" (when sharing .skill package, credentials are exposed).
  - **Risk:** If skill is packaged as .skill, credentials leak to anyone who installs it.
  - **Recommendation:** Remove hardcoded credentials; use environment variables or config file instead.

#### 9. **Test Data Dependency**
- **Lines 275-278:** Test service `sv_test` is hardcoded as the default. Database must have this entry.
  - **Risk:** If DB is reset or service removed, tests fail silently without clear error message.
  - **Recommendation:** Add a check in Pre-flight [2/5] to verify `sv_test` exists in DB.

#### 10. **Testbed <→ Real Service Confusion**
- **Entire skill:** Assumes Dell testbed is always available and working. But if Etap server is down for maintenance, this skill can't help.
  - **Gap:** No fallback for "testbed unavailable — how to test on real services?".
  - **Correct Answer:** Switch to `cowork-remote` (test PC). But this should be explicit.

---

## 3. etap-bench

### Name & Purpose
**Etap DPDK bridge performance benchmark skill.** Measures processing throughput (Mpps), latency, and CPU usage by running pktgen traffic on Dell-1 and varying module on/off configurations. Compares baseline (no modules) vs. +tcpip vs. +VT vs. Full (+VT+APF).

### Metadata
- **Line Count:** 359 lines
- **Language:** Mixed (Korean comments + English commands)
- **Format:** Markdown with embedded bash, pktgen commands, results template

### Key Sections
| Section | Lines | Purpose |
|---------|-------|---------|
| Frontmatter (YAML) | 1-9 | Skill metadata & triggers |
| Purpose | 11-14 | High-level goal |
| 테스트 망 구성 (Topology) | 17-35 | Dell-1 (pktgen TX), Etap (DUT), Dell-2 (RX/nginx) |
| 측정 목적 (Measurement Goal) | 38-56 | What to measure, tool roles (pktgen vs ab/hi vs etapcomm) |
| Pre-flight Checklist | 59-82 | 6 checks ([1/6]) |
| 시나리오 매트릭스 (Scenario Matrix) | 85-106 | 4 configs (A-D), tool matrix |
| Step 1 — 모듈 설정 배포 및 재시작 | 109-133 | Config switching, restart, ready wait |
| Step 2 — pktgen 테스트 (L2/L3) | 137-191 | pktgen setup, stats collection, packet size sweep |
| Step 3 — ab/hi 테스트 (L7) | 194-228 | HTTPS test, POST test, MITM verification |
| Step 4 — 결과 수집 및 비교 | 231-305 | etapcomm stats, pktgen results, report format template |
| 실행 모드 (Execution Modes) | 309-328 | Quick (~3min), Standard (~15min), Full (~45min) |
| 주의사항 (Caveats) | 332-340 | 6 critical warnings (systemctl, Config verification, concurrent testing, warm-up, imissed, VT interpretation) |
| Failure Recovery | 343-351 | 5 error cases |
| Related Skills | 355-359 | etap-testbed, etap-build-deploy |

### Cross-References & Dependencies
**Skills Referenced:**
- `etap-testbed` (line 357) — Module-level functional testing
- `etap-build-deploy` (line 358) — Source modification and rebuild

**External Files Referenced:**
- `references/scenarios.md` (line 87) — Scenario detail procedures, measurement points, result interpretation
- `references/pktgen-commands.md` (line 163) — Detailed pktgen commands

**Configuration Files Referenced:**
- `configs/module_baseline.xml` (line 117) — Config A (no modules)
- `configs/module_{*}.xml` — Configs B, C, D (not explicitly named but implied)

### Trigger Conditions
**Triggers:** "벤치마크", "성능 측정", "pktgen", "Mpps", "throughput", "DPDK 성능", "모듈별 성능 비교", "etap-bench", "performance test"  
**Do NOT Trigger For:** 기능 테스트 (use etap-testbed), 빌드/배포 (use etap-build-deploy)

### Recent Changes & Dates
- **Line 51-55:** Important note added: pktgen measures **hook traversal overhead only**, not actual module processing. VT/APF processing is only visible in ab/hi (L7) tests.
  - This clarifies a major measurement distinction.

### Potential Issues

#### 1. **Outdated/Suspicious References**
- **Line 87:** "See `references/scenarios.md` for 시나리오별 상세 절차" — This file is referenced but not provided in the skill package.
  - **Risk:** User follows matrix (line 85-106) but can't access detailed scenarios.

#### 2. **Broken Cross-References**
- **Line 163:** "See `references/pktgen-commands.md` for 상세 절차" — File not provided.
- **Lines 117-122:** Config files are referenced with paths (`configs/module_baseline.xml`) but **neither the path nor the files are included** in skill.
  - **Risk:** User can't execute Step 1 (Config switching) without these files.

#### 3. **Inconsistencies Between Description & Content**
- **Frontmatter (line 6):** "모듈 on/off에 따른 처리량(Mpps), 지연(latency), CPU 사용률을 측정한다" (measures Mpps, latency, CPU usage).
  - **Content Reality (lines 38-56, 231-305):** Skill measures **Mpps, Gbps, packet loss, req/s, latency, bps, pps, dropPps**. No explicit CPU usage measurement command provided.
  - **Gap:** CPU usage measurement is missing or assumed implicit via `etapcomm etap.port_info`.

#### 4. **Missing Information/Gaps**
- **Lines 139-161:** pktgen test section shows **example** of pktgen commands but with placeholders like `<Dell-2 MAC>`, `set 0 size 1518`, `set 0 rate 100`.
  - **Gap:** How to get Dell-2 MAC? What does "rate 100" mean (100 Gbps? 100%)? Is this Lua script syntax or interactive CLI?
  - **Recommendation:** Provide actual working pktgen example or point to external docs.
- **Lines 89-106:** Scenario matrix specifies which **tools** to use (pktgen vs ab/hi) but not **what results to expect**. How do I know if my numbers are "good"?
  - **Recommendation:** Add baseline expectation ranges (e.g., "Config A baseline: 10-15 Mpps on 64B packets").

#### 5. **Overly Complex Instructions**
- **Lines 115-132:** Config deployment has 4 steps (scp, cp, systemctl, wait loop) but the wait loop (lines 126-129) is cryptic.
  ```
  for i in $(seq 1 30); do
    ssh -p 12222 solution@61.79.198.110 "etapcomm etap.port_info" &>/dev/null && echo "Ready (${i}s)" && break
    sleep 1
  done
  ```
  - **Clarity Issue:** Why 30 iterations? Why check `etap.port_info`? Why discard stdout?
  - **Recommendation:** Add comment explaining: "Wait until etapcomm responds (service fully ready), max 30 seconds."

#### 6. **Duplicate Content Across Skills**
- **Pre-flight Checklist (lines 59-82) vs. etap-testbed Pre-flight (lines 108-134):**
  - Both check: Dell ping, etapd status, instance count, module config, link speed.
  - **Duplication Severity:** High. 95% overlap.
  - **Recommendation:** Create shared `references/shared-preflight.md` or make etap-bench reference etap-testbed's Pre-flight.

#### 7. **Measurement Methodology Gaps**
- **Line 51-55:** Key insight: pktgen doesn't trigger VT/APF (they're L7 modules, pktgen sends raw L2/L3). So Config C/D pktgen results show **only hook overhead**, not actual module cost.
  - **Implication:** If someone naively interprets "Config D pktgen Mpps" as "full stack performance", they'll be wrong.
  - **Caveat is present (line 51)** but might be missed. Recommendation: Highlight in result template (lines 259-305).

#### 8. **Incomplete Result Template**
- **Lines 259-305:** Result template shows placeholders (XX.X Gbps, XX.X Mpps) but **no guidance on how to fill them from raw data**.
  - **Gap:** User captures raw etapcomm output. How do they convert `bps_in=12345` to the "XX.X Gbps" format?
  - **Recommendation:** Add conversion formula section.

#### 9. **Test Isolation Gaps**
- **Line 336:** "pktgen과 ab/hi를 동시 실행하지 말 것" (don't run pktgen and ab/hi simultaneously).
  - **Enforcement:** No automated check. User must manually avoid this. Risk: Accidentally launches both in separate ssh sessions.
  - **Recommendation:** Add a guard script that kills pktgen before ab/hi, or vice versa.

#### 10. **Failure Mode Ambiguity**
- **Line 346-351:** Failure recovery table lists 5 cases (etapd restart fail, pgrep > 1, pktgen fail, VT MITM fail, dropPps).
  - **Gap:** What if **pktgen transmits but Dell-2 doesn't receive**? Is this NIC failure? Etap bridge failure? No diagnosis guide.
  - **Recommendation:** Add packet loss diagnosis (use tcpdump on both Dells, compare TX vs RX).

---

## 4. test-pc-worker

### Name & Purpose
**Windows test PC task executor skill.** Reads task requests from `dev_test_sync/requests/` (sent by dev PC), executes them via PowerShell + browser automation (desktop-commander), and writes results to `results/`. Acts as an autonomous worker in real-network (실망) environment running Etap client. Handles APF blocking/warning verification, certificate checks, and general web testing.

### Metadata
- **Line Count:** 352 lines
- **Language:** Mixed (Korean conceptual, English procedural)
- **Format:** Markdown with PowerShell examples, JSON state specs

### Key Sections
| Section | Lines | Purpose |
|---------|-------|---------|
| Frontmatter (YAML) | 1-12 | Skill metadata & triggers |
| Purpose | 14-34 | Why this PC needed, why desktop-commander, constraints |
| Environment | 37-63 | OS, tools, file paths, Git config, desktop-commander mappings |
| Folder Structure | 69-107 | Git repo layout, local_archive/state.json, session state file |
| Operation Modes | 111-163 | Mode 1: user-directed, Mode 2: auto-polling (1min/10min/1hr stages) |
| Execution Flow (Step 0-1) | 167-188 | Session start recovery via session-recovery.ps1, git pull, request scan |
| Step 2 — Request Execution | 189-227 | Ensure-ChromeMaximized, DevTools rules, screenshot standards |
| Step 3 — Result Writing + State Update | 229-250 | write-result.ps1, metrics collection |
| Step 3.5 — Metrics Collection | 242-250 | Phase timing (browser_focus, prompt_input, wait_response, screenshot, analysis) |
| Step 4 — Git Push + Delivery | 253-262 | git_sync.bat push only, verification check, conditional last_delivered_id update |
| Step 5 — Completion Report | 263-273 | Brief summary, cleanup temp files |
| Test Sensitive Keyword | 276-281 | "한글날" (Korean Thanksgiving) — APF test keyword |
| Error Handling | 285-305 | 8 error patterns with diagnosis & recovery |
| Command Overview | 308-328 | APF (check-block, check-warning) + web test (check-cert, check-page, etc.) |
| Batch Processing | 332-344 | Multiple requests: urgent first, sequential, immediate result write |
| Related Skills | 347-352 | cowork-remote, genai-warning-pipeline, desktop-commander |

### Cross-References & Dependencies
**Skills Referenced:**
- `cowork-remote` (dev PC side) — Counterpart skill that sends requests
- `genai-warning-pipeline` (Phase 1, 3) — Sends test tasks
- `desktop-commander` (MCP) — Core execution tool

**Scripts Referenced:**
- `scripts/windows/session-recovery.ps1` (line 177) — Session start recovery
- `scripts/windows/write-result.ps1` (line 231) — Result JSON + state update
- `references/windows-commands.md` (line 204) — Per-command execution details
- `references/browser-rules.md` (line 205) — Browser setup & DevTools rules
- `references/error-patterns.md` (line 304) — Error diagnosis
- `references/result-templates.md` (line 240) — JSON templates
- `references/metrics-collection.md` (line 250) — Metrics recording details
- `references/phase-definitions.md` (line 251) — Command-specific phase timing

**Configuration Files:**
- `local_archive/state.json` (lines 90-107) — Session state (last_processed_id, last_delivered_id, polling_active, last_error)

### Trigger Conditions
**Triggers:** "새 요청 확인", "작업 처리", "폴링 시작", "자동으로 확인", "dev에서 요청 왔어?", "check-block", "check-warning", "테스트 실행"  
**Implied Triggers:** Any request reading/execution task on Windows test PC

### Recent Changes & Dates
- **Line 138-149:** "적응형 폴링 (Adaptive Polling)" section added — 3-stage polling (1min/10min/1hr) with stage backoff to reduce server load.
- **Lines 150-158:** "Heartbeat 기록" mechanism added — write `results/heartbeat.json` every poll cycle for dev PC to detect test PC availability.
- **Lines 127-131:** "폴링 시작 전 체크리스트" added — guards against stale skill memory and ensures state recovery.

### Potential Issues

#### 1. **Outdated References**
- **Line 138-149:** Adaptive polling implementation ("1분 간격 × 10회 → Stage 2로 전환") is described but **no code provided**. Where is this implemented? In session-recovery.ps1? In test-pc-worker itself?
  - **Risk:** User reads this, expects adaptive polling, but no actual implementation exists.

#### 2. **Broken Cross-References**
- **Lines 204-205, 217-218, 240, 250-251, 304:** All reference `references/` files (windows-commands.md, browser-rules.md, result-templates.md, metrics-collection.md, phase-definitions.md, error-patterns.md).
  - **Issue:** These files are not provided in skill. Are they in Git? Are they autogenerated?
  - **Risk:** User can't execute without these files.

#### 3. **Inconsistencies Between Description & Content**
- **Frontmatter (lines 3-8):** "AI 서비스 차단/경고 확인, 인증서 확인, 페이지 동작 확인 등 웹 테스트 전반을 담당" (APF blocking/warning, cert, page checks).
  - **Content (lines 310-327):** 6 main commands (check-block, check-warning, check-cert, check-page, capture-screenshot, verify-access) + 3 advanced (run-scenario, report-status). Description matches.
  - **Consistency:** Good.

#### 4. **Missing Information/Gaps**
- **Lines 189-227:** Step 2 describes "매 작업 시작 시 표준 화면 배열" (standard screen layout) and "Ensure-ChromeMaximized" but **no guidance on what this function does or how to call it**.
  - **Gap:** User must read `references/windows-commands.md` § 공통 유틸리티. But that file is not provided.
  - **Recommendation:** Include function definition or code snippet inline.
- **Lines 232-250:** Metrics collection mentions `results/metrics/metrics_{date}.jsonl` but **doesn't specify where to read phase_timings from or how to calculate them**. Are they captured by PowerShell stopwatch? By browser DevTools timing?
  - **Recommendation:** Add example PowerShell code for `Stopwatch` usage.

#### 5. **Overly Complex Instructions**
- **Lines 150-158:** Heartbeat mechanism (write JSON every poll cycle) is described in 9 lines + PowerShell snippet. Purpose is clear, but implementation details are sparse.
  - **Complexity Issue:** User must understand why heartbeat exists (for dev PC diagnostics) vs. just copying the code.
  - **Recommendation:** Add a comment block explaining: "Heartbeat allows dev PC to detect test PC downtime without log analysis."

#### 6. **Duplicate Content Across Skills**
- **Folder Structure (lines 69-107) vs. cowork-remote Folder Structure (lines 327-356):**
  - Both describe the same Git repo layout (requests/, results/, local_archive/, state.json).
  - **Duplication Severity:** High. 90% overlap.
  - **Issue:** If state.json schema changes, both skills must be updated.
  - **Recommendation:** Define schema once in `cowork-remote/references/protocol.md`, reference from both.

#### 7. **Error Recovery Limitations**
- **Lines 285-305:** 8 error patterns with recovery steps. But **if PowerShell script crashes** (e.g., out-of-memory), how is the task marked as failed?
  - **Gap:** No try-catch wrapper visible. If script dies, does write-result.ps1 run? Or is the task lost?
  - **Recommendation:** Wrap entire Step 2 in try-finally to ensure result is written even on error.

#### 8. **State File Ambiguity**
- **Lines 90-107:** state.json describes 5 fields: last_processed_id, last_delivered_id, polling_active, last_error, updated_at.
  - **Gap:** What if **two concurrent sessions** modify state.json? Is there a lock?
  - **Recommendation:** Add note: "state.json should only be modified by one session at a time. Concurrent modifications will corrupt the file."

#### 9. **Polling Termination Conditions**
- **Lines 159-163:** Polling ends if:
  - (a) User says "멈춰", "중단", "stop"
  - (b) Error 3 times in a row
  - **Gap:** What if a task is slow (takes 5 minutes)? Does polling stall? Does the scheduler timeout and kill the session?
  - **Recommendation:** Specify max task duration and cleanup on timeout.

#### 10. **Browser State Persistence**
- **Lines 194-202:** Every task starts with `Ensure-ChromeMaximized` to reset browser state. But **if previous task left browser in broken state** (e.g., certificate warning dialog), does reset handle it?
  - **Gap:** No guidance on how to dismiss persistent dialogs.
  - **Recommendation:** Add step: "If [certificate warning] dialog visible, click 'Proceed Anyway'."

---

## 5. cowork-remote

### Name & Purpose
**Dev-Test PC remote collaboration skill.** Orchestrates asynchronous task exchange between dev PC (Git repo management) and test PC (execution) via `dev_test_sync` Git repository. Enables dev to send verification requests, test PC to execute and report results, and both to track state without direct network connection. Supports both user-directed mode (manual task send/check) and Scheduled Task mode (autonomous polling + decision-making).

### Metadata
- **Line Count:** 467 lines
- **Language:** Mixed (Korean conceptual, English procedural)
- **Format:** Markdown with JSON schema, bash/PowerShell examples, state diagrams

### Key Sections
| Section | Lines | Purpose |
|---------|-------|---------|
| Frontmatter (YAML) | 1-17 | Skill metadata & triggers |
| Purpose | 19-35 | Why Git-based async protocol, test PC role, APF focus (but generic framework) |
| CRITICAL RULES | 39-103 | 4 immutable rules: (1a) Polling never stops, (1b) 30min stall escalation, (2) no user confirmation in polling, (3) write direction separation, (4) skill tool delegation |
| BEHAVIORAL RULES | 105-131 | Auto-SUSPEND on 3 identical failures, 5 failure categories |
| Shared Path (Git Sync) | 135-167 | Path mapping (Mac dev → Windows test), tool selection (GitHub MCP vs git CLI vs desktop-commander), Scheduled Task constraints |
| Role Determination | 170-189 | Auto-detect dev/test role, fallback user question, reference to role-specific workflows |
| Operation Modes | 192-323 | Mode 1: user-directed (default), Mode 2: auto-polling via Scheduled Task |
| Folder Structure | 327-375 | Git repo layout (requests/, results/, local_archive/, queue.json, etc.) |
| Task Lifecycle | 378-395 | State diagram (dev create → test execute → dev read → archive) |
| Quick Reference | 401-416 | Action table with who/folder/reference |
| Common Task Types | 420-440 | APF (check-block, check-warning) + web tests |
| Context Recovery | 444-455 | Session resume handling (resume/compact history) |
| Related Skills | 459-467 | test-pc-worker, workflow-retrospective, genai-warning-pipeline, genai-apf-pipeline, etap-build-deploy |

### Cross-References & Dependencies
**Skills Referenced:**
- `test-pc-worker` (test PC execution) — Implements task execution, captures metrics
- `workflow-retrospective` (dev PC) — Analyzes metrics, suggests optimizations
- `genai-warning-pipeline` (dev PC) — Phase 1, 3 send test requests
- `genai-apf-pipeline` (backup) — Prior pipeline
- `etap-build-deploy` (dev PC) — Build/deploy before test

**Scripts Referenced:**
- `scripts/mac/send-request.sh` (line 229) — Request creation & push (with rebase retry)
- `scripts/mac/scan_results.sh` (line 411) — Filesystem scan for new results (not git pull)
- `scripts/mac/regen-status.sh` (line 237) — Regenerate status.md from impl journal
- `scripts/windows/session-recovery.ps1` (line 177 in test-pc-worker) — test PC recovery

**Reference Files (role-specific workflows):**
- `references/dev-workflow.md` (line 186)
- `references/test-workflow.md` (line 186)
- `references/protocol.md` (line 397, 440) — JSON schemas, file naming
- `references/pipeline-state-schema.md` (line 272, 131) — service_queue, failure_history
- `references/visual-diagnosis.md` (line 305) — AnyDesk screenshot diagnosis procedures
- `references/git-push-guide.md` (line 261, 88) — Git push validation, forbidden patterns
- `references/delivery-guide.md` (line 462) — How to deliver skill to test PC
- `references/test-pc-prompt.md` (line 463) — test PC initial setup prompt

**State Files:**
- `queue.json` (line 331) — Shared task queue overview
- `pipeline_state.json` (lines 258-271) — Scheduled Task state (service_queue, work_context, monitoring)
- `pipeline_dashboard.md` (lines 274-279) — User-facing progress dashboard
- `local_archive/state.json` (dev, line 360; test, implicit in test-pc-worker) — Session state tracking

### Trigger Conditions
**Triggers:** "원격 작업", "test PC", "작업 전달", "큐 확인", "결과 확인", "test PC에 요청", "원격에 보내줘", "테스트 PC에서 확인해줘", "큐 상태", "새 요청 있어?", "자동으로 확인해줘", "폴링", "모니터링"  
**Cross-PC Coordination:** Task status checks, result reading from other PC

### Recent Changes & Dates
- **Lines 55-81:** §1b "정체 에스컬레이션" (Stall Escalation) rule added. After 6 empty polls (~30min stall), mark service STALLED, move to next in queue, macOS notification. **This is a critical new rule** addressing infinite wait scenario from 4/10 incident review.
- **Lines 109-130:** §Auto-SUSPEND rule added. 3 identical failures in a row → suspend service from testing. This addresses Mistral case where 10 failed attempts repeated the same issue.
- **Lines 214-222:** GitHub MCP vs git CLI split documented. Scheduled Task can't use GitHub MCP (auth limitation verified 2026-03-25), must use git CLI.
- **Lines 233-255:** Scheduled Task workflow detailed with recovery scan, git pull, result detection, auto-action, state update, dashboard update, macOS notifications.

### Potential Issues

#### 1. **Outdated/Suspicious Architecture Shifts**
- **Lines 233-255:** Scheduled Task workflow description is recent and detailed. But **no code provided** to implement this workflow.
  - **Risk:** User reads this, expects Scheduled Task to auto-run polling, but code doesn't exist or is incomplete.
  - **Recommendation:** Provide Scheduled Task shell script (bash for Mac) or document its location.
- **Line 214:** GitHub MCP auth limitation in Scheduled Task "검증 완료" (verification complete). **When was this verified?** No date given. If this was 3+ months ago, auth landscape may have changed.

#### 2. **Broken Cross-References**
- **Lines 186, 261, 272, 305, 305, 323, 462, 463:** References to `references/` files.
  - **Issue:** None of these files provided in skill.
  - **Severity:** High. User can't execute Scheduled Task workflow, context recovery, or deployment without these docs.

#### 3. **Inconsistencies Between Description & Content**
- **Purpose (lines 19-35):** "APF 관련 작업이 주 작업이 될 예정이지만, 이 스킬은 범용 웹 테스트 협업에 사용할 수 있다" (APF is main task for now, but skill is generic web testing).
  - **Content (lines 420-440):** 2 APF commands + 6 generic web commands. Description matches.
  - **Consistency:** Good.
- **§1a Polling Never Stops (lines 43-54) vs. §1b Stall Escalation (lines 55-81):**
  - **Apparent Conflict:** §1a says "폴링 루프는 절대 종료하지 않는다" (polling never stops). §1b says "다음 서비스로 진행" (move to next service on 30min stall).
  - **Clarification Needed:** Does §1b "move to next service" mean "pause current service" or "abandon current service forever"? If pause, when does it resume?
  - **Current Text (line 66):** "stall_count 리셋 후 **폴링 계속**" (reset counter, polling continues). This clarifies that polling continues, just moving to next service. But wording is subtle.

#### 4. **Missing Information/Gaps**
- **Lines 237-255:** Scheduled Task recovery scan, git pull, result detection, auto-action are described in ~20 lines.
  - **Gap:** What IS auto-action? The skill says "Scheduled Task는 결과를 감지하고 분석한 후 **다음 액션까지 실행**해야 한다" (must execute through next action). But what actions?
  - **Answer (implied):** See Scheduled Task prompt. But no prompt provided here.
  - **Recommendation:** At minimum, list 3-5 auto-actions (e.g., "retry request", "escalate to L3 diagnosis", "mark SUSPENDED").

- **Lines 287-304:** L3 Visual Diagnosis mechanism described: 30min stall → set monitoring.visual_needed=true → main session checks via AnyDesk → analysis → action.
  - **Gap:** This requires **main session** to be running. But Scheduled Task is independent. If user is asleep and Scheduled Task detects stall, how does L3 happen?
  - **Implication:** L3 diagnosis only works during business hours when user is available.
  - **Recommendation:** Document this async limitation.

- **Lines 258-271:** pipeline_state.json schema shown but **no example of failure_history structure**. What does {category, result_status, request_id, build} look like as JSON?
  - **Recommendation:** Show example:
    ```json
    "failure_history": [
      {"category": "NOT_RENDERED", "status": "failed", "req_id": 45, "build": 201},
      {"category": "NOT_RENDERED", "status": "failed", "req_id": 46, "build": 201},
      {"category": "NOT_RENDERED", "status": "failed", "req_id": 47, "build": 201}
    ]
    ```

#### 5. **Overly Complex Instructions**
- **Lines 55-81:** §1b Stall Escalation is described in 27 lines with example. Good detail, but the example uses "stall_count >= 6 (5分 간격 기준 약 30분)" — where does 5min interval come from? Is this hardcoded or configurable?
  - **Ambiguity:** If polling interval is 1min (line 139), then 6 polls = 6min, not 30min. If interval is 5min, 6 polls = 30min. **Which is it?**
  - **Recommendation:** Specify actual polling interval clearly.

#### 6. **Duplicate Content Across Skills**
- **Folder Structure (lines 327-375) vs. test-pc-worker Folder Structure (lines 69-107):**
  - 95% overlap.
  - **Duplication Severity:** Very High.
  - **Recommendation:** Define canonical schema in `cowork-remote/references/protocol.md`, reference from test-pc-worker.

- **Role Determination (lines 170-189) vs. test-pc-worker Environment (lines 37-63):**
  - Both mention auto-role detection (dev/test).
  - **Duplication Severity:** Medium.

#### 7. **Critical Rule Violations Risk**
- **§1a (lines 43-54):** "폴링 루프는 절대 종료하지 않는다" (polling never stops).
  - **Context:** This applies to Scheduled Task polling only. But **what if user manually triggers this skill on dev PC and asks "check results"?** Does this skill also start polling?
  - **Answer:** Not clear from skill. User might start polling unintentionally.
  - **Recommendation:** Add explicit guard: "In user-directed mode (Mode 1), this skill does NOT auto-poll. User must explicitly say 'start polling' to enter Mode 2."

#### 8. **Scheduled Task Dependency Issues**
- **Lines 307-322:** Scheduled Task creation/management shown via `create_scheduled_task`, `update_scheduled_task`.
  - **Gap:** These are separate tool calls. If user calls create_scheduled_task but it fails, does the skill catch the error and report it? Or does it assume success and proceed?
  - **Recommendation:** Wrap in try-catch and report success/failure.

#### 9. **macOS Notification Assumptions**
- **Lines 281-286:** Skill sends macOS notifications via `osascript`. But **what if user is on Windows or Linux?** This skill is supposedly dev/test agnostic, but notifications are Mac-only.
  - **Recommendation:** Add platform detection: `if os == "darwin" { osascript ... } else { print to console }`

#### 10. **Git Conflict Handling Gap**
- **Lines 142-144:** Shared path uses GitHub MCP `push_files` for dev, which "여러 파일 한번에 push 가능".
  - **Gap:** What if **git merge conflict** occurs during `git pull`? Skill doesn't mention conflict resolution.
  - **Recommendation:** Document: "If git pull detects conflicts, run `git merge --abort` and notify user."

---

## Cross-Skill Analysis Summary

### 1. **Interconnection Map**

```
etap-build-deploy
├── Referenced by: etap-testbed (line 391)
├── Referenced by: etap-bench (line 358)
├── Referenced by: genai-warning-pipeline (implied, Phase 4)
└── References: dev_test_sync scripts, genai-warning-pipeline (line 506)

etap-testbed
├── Referenced by: genai-apf-pipeline (line 392)
├── References: etap-build-deploy (line 391)
└── References: references/troubleshooting.md, vt-test-guide.md, db-queries.md

etap-bench
├── References: etap-testbed (line 357)
├── References: etap-build-deploy (line 358)
└── References: references/scenarios.md, pktgen-commands.md

test-pc-worker
├── References: cowork-remote (line 349)
├── Referenced by: cowork-remote (line 461)
├── Referenced by: genai-warning-pipeline (Phase 1, 3)
└── Uses: desktop-commander (MCP)

cowork-remote
├── References: test-pc-worker (line 461)
├── References: genai-warning-pipeline (line 466)
├── References: genai-apf-pipeline (implied, Phase 1)
├── References: etap-build-deploy (line 466)
├── References: workflow-retrospective (line 464)
└── References: references/dev-workflow.md, test-workflow.md, protocol.md
```

### 2. **Missing Files Critical List**

Files referenced but NOT provided in skills:
- `references/troubleshooting.md` (etap-testbed)
- `references/vt-test-guide.md` (etap-testbed)
- `references/etapcomm-commands.md` (etap-testbed)
- `references/db-queries.md` (etap-testbed)
- `references/scenarios.md` (etap-bench)
- `references/pktgen-commands.md` (etap-bench)
- `references/windows-commands.md` (test-pc-worker)
- `references/browser-rules.md` (test-pc-worker)
- `references/error-patterns.md` (test-pc-worker)
- `references/result-templates.md` (test-pc-worker)
- `references/metrics-collection.md` (test-pc-worker)
- `references/phase-definitions.md` (test-pc-worker)
- `references/dev-workflow.md` (cowork-remote)
- `references/test-workflow.md` (cowork-remote)
- `references/protocol.md` (cowork-remote)
- `references/pipeline-state-schema.md` (cowork-remote)
- `references/visual-diagnosis.md` (cowork-remote)
- `references/git-push-guide.md` (cowork-remote)
- `references/delivery-guide.md` (cowork-remote)
- `references/test-pc-prompt.md` (cowork-remote)

**Total Missing:** 20 reference files

### 3. **High-Risk Inconsistencies**

| Issue | Skills Affected | Severity |
|-------|-----------------|----------|
| Hardcoded server IPs/ports expose credentials if skill shared | etap-testbed, etap-build-deploy | HIGH |
| 20 missing reference files prevent execution | all 5 | CRITICAL |
| Polling stall escalation (30min timeout) vs polling-never-stops conflict | cowork-remote | MEDIUM |
| Path/config drift risk — memory-dependent | etap-build-deploy | MEDIUM |
| Package filename collision (same YYMMDD overwrites) | etap-build-deploy | MEDIUM |
| Pre-flight checklists duplicated across 4 skills | etap-testbed, etap-bench, test-pc-worker, cowork-remote | MEDIUM |
| testbed module test ≠ real-service test (cowork-remote confusion) | etap-testbed, cowork-remote | MEDIUM |
| Role detection ambiguous if skill appears in wrong PC context | cowork-remote | LOW-MEDIUM |

### 4. **Recommendations for Batch 2 Skills**

**Priority 1 (Blocking):**
1. Create all 20 missing `references/` files or merge content into main skill docs
2. Move hardcoded credentials (IPs, ports) to config files
3. Document exact polling interval (is it 1min or 5min?) in cowork-remote
4. Provide Scheduled Task implementation code for cowork-remote

**Priority 2 (High Impact):**
1. Consolidate Pre-flight Checklists into `references/shared-preflight.md`
2. Create `references/protocol.md` schema covering all JSON formats
3. Add explicit decision trees (e.g., "use etap-testbed or etap-build-deploy?")
4. Document failure recovery for tarball corruption/symlink destruction

**Priority 3 (Quality):**
1. Add pktgen baseline expectations (Mpps ranges per packet size)
2. Clarify "closed testbed" terminology (closed among 3 servers, not externally)
3. Add examples of module.xml for disabling specific modules
4. Document context recovery for polling resume after session break

**Priority 4 (Completeness):**
1. Include browser automation function definitions (Ensure-ChromeMaximized)
2. Add Python/bash conversion scripts for etapcomm output → benchmark template
3. Document max task duration and timeout cleanup for test-pc-worker
4. Add cross-platform notification support (not just macOS)

