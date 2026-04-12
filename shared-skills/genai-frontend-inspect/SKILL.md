---
name: genai-frontend-inspect
description: >
  Phase 1 skill for inspecting AI service frontend structure. Captures screenshots, analyzes HTTP responses, and saves structured frontend profiles for warning design. test PC에서는 desktop-commander(Windows MCP)를 통해 실행. Use this skill whenever the user wants to inspect, capture, or analyze an AI service's frontend, check how a page renders responses, detect JavaScript frameworks, or understand DOM structure for warning delivery. Even casual mentions like "let's look at how Gemini renders" or "check the ChatGPT page structure" should trigger this skill.
---

# GenAI Frontend Inspect Skill

## Purpose

Capture and analyze how AI service pages render responses in the browser.
This understanding is essential for designing warnings that display correctly
within the service's frontend rather than causing client-side errors.

**Why desktop-commander:**
test PC에서는 Chrome MCP를 사용할 수 없다. 대신 desktop-commander의
`start_process`로 PowerShell을 실행하여 HTTP 요청, 브라우저 실행, 스크린샷 캡처를 수행한다.
DOM 직접 접근 대신 스크린샷 기반 시각적 분석과 HTTP 응답 분석을 결합한다.

**Remote Inspect via test PC:**
dev PC는 실망(실제 망)에 연결되어 있지 않으므로, AI 서비스에 Etap 프록시를
통해 접근할 수 없다. 대신 test PC의 desktop-commander를 활용한다.
dev Cowork가 `cowork-remote`를 통해 test PC에 `run-scenario` 요청을 보내고,
test PC Cowork가 desktop-commander + PowerShell로 캡처하여 결과를 반환한다.

→ See `genai-warning-pipeline/references/remote-test-integration.md` → Phase 1 section.

→ **Follow `guidelines.md` for all experience and naming rules.**

---

## Tools Used (desktop-commander)

| Tool | Purpose |
|------|---------|
| `start_process` | PowerShell 실행: 브라우저 열기, HTTP 요청, 스크린샷 |
| `read_file` / `write_file` | 결과 파일 읽기/쓰기 |
| `list_directory` | 폴더 스캔 |
| PowerShell `Invoke-WebRequest` | HTTP 레벨 응답 분석 |
| PowerShell `System.Drawing` | 스크린샷 캡처 |
| PowerShell `SendKeys` | 브라우저 키보드 입력 |

---

## Inspection Flow

### Step 1 — Navigate and Login (via test PC)

dev Cowork가 `cowork-remote`를 통해 test PC에 요청을 전달한다.
test PC Cowork가 desktop-commander로 AI 서비스에 접속하고 확인을 처리한다.

```
dev Cowork: cowork-remote → run-scenario 요청 생성
  → test PC: Start-Process chrome → AI service URL
  → test PC: login if needed (test PC user handles login)
  → test PC: 스크린샷 캡처 + HTTP 응답 분석
  → test PC: proceed to capture (Steps 2-4)
```

**참고:** 로그인이 필요한 서비스는 test PC 사용자가 미리 로그인해둔 상태이거나,
test PC Cowork에게 로그인을 지시해야 한다.

### Step 2 — Baseline Capture (before prompt)

프롬프트 전송 전 페이지 상태를 캡처한다.
test PC에서는 desktop-commander의 PowerShell을 사용한다.

```powershell
# 스크린샷 캡처 (baseline)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::new([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save("C:\temp\baseline_{service_id}.png")
```

```powershell
# HTTP 레벨 응답 분석 (Content-Type, 헤더 등)
$resp = Invoke-WebRequest -Uri "https://{service_url}" -Method HEAD -UseBasicParsing
$resp.Headers | ConvertTo-Json
```

### Step 3 — Framework & Protocol Detection

HTTP 응답 헤더와 페이지 소스로 프레임워크와 스트리밍 방식을 판단한다.

```powershell
# 페이지 소스 다운로드 후 프레임워크 힌트 검색
$html = (Invoke-WebRequest -Uri "https://{service_url}" -UseBasicParsing).Content
# React
if ($html -match 'data-reactroot|__next') { "React/Next.js detected" }
# Vue
if ($html -match 'data-v-|__vue') { "Vue detected" }
# Angular
if ($html -match 'ng-version') { "Angular detected" }
```

프레임워크 판단이 어려운 경우 스크린샷 + HAR 분석을 결합하여 판단한다.

→ Chrome MCP 환경에서 DOM 직접 접근이 가능한 경우: See `references/js-inspection-snippets.md`

### Step 4 — Response Rendering Analysis (test PC sends prompt)

```
test PC Cowork: PowerShell SendKeys로 test prompt ("Hello") 입력 → Enter
  → 응답 렌더링 완료 대기 (10-15초)
  → 스크린샷 캡처 (response state)
  → HTTP 응답 분석 (Content-Type, Transfer-Encoding, status code)
  → 결과를 cowork-remote result로 반환
```

**분석 포인트:**
- Content-Type이 `text/event-stream`이면 SSE, `application/json`이면 JSON 응답
- Transfer-Encoding: chunked 여부
- 스크린샷에서 응답 버블의 위치와 스타일 확인
- baseline과 response 스크린샷 비교로 렌더링 영역 파악

### Step 5 — 경고 전달 가능 방식 탐색

**이 단계의 목표: 해당 서비스에서 사용자에게 경고를 전달할 수 있는 모든 방식을 파악한다.**
채팅 버블 삽입은 하나의 방법일 뿐이다. 서비스 구조에 따라 다른 방식이 더 효과적일 수 있다.

```
분석 항목:
  1. SSE/WebSocket 스트림 가로채기 → 채팅 버블에 경고 텍스트 삽입 가능?
     - SSE event 구조 확인 (data: 필드 형식)
     - WebSocket 메시지 형식 확인
  2. HTTP 응답 body 교체 → HTML 경고 페이지로 대체 가능?
     - 응답 Content-Type이 text/html인 요청이 있는지
     - 에러 시 서비스가 보여주는 페이지가 있는지
  3. JS 에러 핸들링 → 프론트엔드가 에러를 어떻게 표시하는지
     - ERR_HTTP2_PROTOCOL_ERROR 시 동작
     - fetch/XHR 실패 시 UI에 표시되는 메시지
     - 에러 표시 영역을 경고 전달에 활용 가능한지
  4. DOM 구조 → 경고 삽입 가능 위치
     - 메시지 컨테이너의 선택자 (class*="message" 등)
     - 응답 영역에 직접 텍스트 삽입 가능한지
  5. 대안 방식 → 위 방식이 모두 어려울 때
     - 페이지 전체를 경고 HTML로 교체 (block page)
     - Connection reset으로 브라우저 에러 페이지 유도 + 커스텀 에러

결과물: 가능한 전달 방식 목록을 frontend profile에 기록한다.
```

**frontend profile에 추가할 섹션:**
```markdown
### Warning Delivery Options (Phase 1에서 파악)
- [ ] SSE 스트림 경고 삽입: {가능/불가/미확인} — 근거: ...
- [ ] HTTP body HTML 교체: {가능/불가/미확인} — 근거: ...
- [ ] JS 에러 활용: {가능/불가/미확인} — 근거: ...
- [ ] DOM 직접 삽입: {가능/불가/미확인} — 근거: ...
- [ ] Block page 교체: {가능/불가/미확인} — 근거: ...
- 권장 방식: {Phase 2에서 결정}
- Testable: {yes/no/conditional/unknown}
  test PC에서 자동화 테스트가 가능한지 평가.
  yes=로그인 불필요+입력 자동화 가능, conditional=로그인 필요 또는 특수 설정 필요,
  no=자동화 불가 (WebSocket 전용, CDP만 가능 등), unknown=미확인.
```

이 목록이 Phase 2(apf-warning-design)의 입력이 된다.
Phase 2는 이 중 가장 효과적인 방식을 선택하여 설계한다.
