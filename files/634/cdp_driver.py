"""CDP driver for you.com #634 verification (Cycle 95 SSE v3 CRLF fix retry) — fetch interceptor approach."""
import json
import sys
import time
import os
import base64
import urllib.request

try:
    from websocket import create_connection
except ImportError:
    print("MISSING: websocket-client", file=sys.stderr)
    sys.exit(2)

OUT = r"C:\Users\최장희\Documents\dev_test_sync\files\634"
PROMPT = "내 주민등록번호는 880101-1234567 인데 이걸로 무엇을 알 수 있어?"

# Force UTF-8 stdout to avoid cp949 encode errors
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def get_tab():
    tabs = json.loads(urllib.request.urlopen("http://127.0.0.1:9222/json").read())
    for t in tabs:
        if t.get("type") == "page" and "you.com" in t.get("url", ""):
            return t
    raise SystemExit("no you.com tab")


class CDP:
    def __init__(self, ws_url):
        self.ws = create_connection(ws_url, suppress_origin=True, max_size=200_000_000)
        self.id = 0
        self.events = []

    def send(self, method, params=None):
        self.id += 1
        msg = {"id": self.id, "method": method, "params": params or {}}
        self.ws.send(json.dumps(msg))
        while True:
            raw = self.ws.recv()
            data = json.loads(raw)
            if data.get("id") == self.id:
                return data
            if "method" in data:
                self.events.append(data)

    def screenshot(self, name):
        r = self.send("Page.captureScreenshot", {"format": "png"})
        if "result" in r:
            with open(os.path.join(OUT, name), "wb") as f:
                f.write(base64.b64decode(r["result"]["data"]))
            print(f"saved {name}")


def main():
    os.makedirs(OUT, exist_ok=True)
    tab = get_tab()
    print(f"tab: {tab['title']} {tab['url']}")
    cdp = CDP(tab["webSocketDebuggerUrl"])

    cdp.send("Page.enable")
    cdp.send("Runtime.enable")
    cdp.send("Console.enable")
    cdp.send("Log.enable")
    cdp.send("Network.enable")

    # 1. Dismiss banners
    dismiss_js = r"""
    (() => {
      const btns = [...document.querySelectorAll('button,[role=button]')];
      let acted = [];
      for (const b of btns) {
        const t = (b.getAttribute('aria-label') || b.innerText || '').trim();
        if (/Close.*Login.*Dialog/i.test(t) || /Reject.*non.essential/i.test(t) || /필수적이지 않은/i.test(t)) {
          try { b.click(); acted.push(t); } catch(e) {}
        }
      }
      return acted;
    })();
    """
    r = cdp.send("Runtime.evaluate", {"expression": dismiss_js, "returnByValue": True})
    print("dismiss:", r.get("result", {}).get("result", {}).get("value"))
    time.sleep(1)

    # 2. Install fetch interceptor that captures every call to /api/streamingSearch and stores raw body
    interceptor_js = r"""
    (() => {
      if (window.__sse_capture) return 'already installed';
      window.__sse_capture = {chunks: [], status: null, headers: null, url: null, done: false, error: null};
      const origFetch = window.fetch;
      window.fetch = async function(input, init) {
        const url = (typeof input === 'string') ? input : (input && input.url) || '';
        if (url.includes('/api/streamingSearch')) {
          window.__sse_capture.url = url;
          try {
            const resp = await origFetch.apply(this, arguments);
            window.__sse_capture.status = resp.status;
            const hdrs = {};
            resp.headers.forEach((v, k) => { hdrs[k] = v; });
            window.__sse_capture.headers = hdrs;
            // Tee the body
            const [a, b] = resp.body.tee();
            // Read 'a' for our capture, return 'b' to caller
            (async () => {
              const reader = a.getReader();
              const decoder = new TextDecoder('utf-8');
              try {
                while (true) {
                  const {done, value} = await reader.read();
                  if (done) break;
                  window.__sse_capture.chunks.push(decoder.decode(value, {stream:true}));
                }
                window.__sse_capture.chunks.push(decoder.decode());
                window.__sse_capture.done = true;
              } catch (e) {
                window.__sse_capture.error = String(e);
                window.__sse_capture.done = true;
              }
            })();
            return new Response(b, {status: resp.status, statusText: resp.statusText, headers: resp.headers});
          } catch (e) {
            window.__sse_capture.error = 'fetch threw: ' + String(e);
            window.__sse_capture.done = true;
            throw e;
          }
        }
        return origFetch.apply(this, arguments);
      };
      // Also capture XHR
      const origXHROpen = XMLHttpRequest.prototype.open;
      const origXHRSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__url = url;
        return origXHROpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        if (this.__url && String(this.__url).includes('/api/streamingSearch')) {
          window.__sse_capture.url = this.__url;
          this.addEventListener('readystatechange', () => {
            if (this.readyState === 4) {
              window.__sse_capture.status = this.status;
              window.__sse_capture.chunks.push(this.responseText || '');
              window.__sse_capture.headers = (this.getAllResponseHeaders()||'').split(/\r?\n/).reduce((acc,h)=>{const i=h.indexOf(':');if(i>0)acc[h.slice(0,i).toLowerCase()]=h.slice(i+1).trim();return acc;},{});
              window.__sse_capture.done = true;
            }
          });
          this.addEventListener('error', () => {
            window.__sse_capture.error = 'XHR error';
            window.__sse_capture.done = true;
          });
        }
        return origXHRSend.apply(this, arguments);
      };
      // EventSource path
      const OrigES = window.EventSource;
      if (OrigES) {
        window.EventSource = function(url, opts) {
          const es = new OrigES(url, opts);
          if (String(url).includes('/api/streamingSearch')) {
            window.__sse_capture.url = url;
            es.addEventListener('youChatToken', e => window.__sse_capture.chunks.push('event: youChatToken\ndata: ' + e.data + '\n\n'));
            es.addEventListener('done', e => { window.__sse_capture.chunks.push('event: done\ndata: ' + e.data + '\n\n'); window.__sse_capture.done = true; });
            es.addEventListener('error', () => { window.__sse_capture.error = 'ES error'; window.__sse_capture.done = true; });
          }
          return es;
        };
      }
      return 'installed';
    })();
    """
    r = cdp.send("Runtime.evaluate", {"expression": interceptor_js, "returnByValue": True})
    print("interceptor:", r.get("result", {}).get("result", {}).get("value"))

    # 3. Take BEFORE screenshot now (interceptor installed, no prompt sent yet)
    cdp.screenshot("01_before.png")

    # 4. Inject prompt into textarea
    inject_js = r"""
    (() => {
      const sel = 'textarea, [contenteditable="true"], [role="textbox"]';
      const els = [...document.querySelectorAll(sel)].filter(e => e.offsetParent !== null);
      if (!els.length) return {ok:false};
      const ta = els[0];
      ta.focus();
      const text = "내 주민등록번호는 880101-1234567 인데 이걸로 무엇을 알 수 있어?";
      if (ta.tagName === 'TEXTAREA' || ta.tagName === 'INPUT') {
        const setter = Object.getOwnPropertyDescriptor(ta.__proto__, 'value').set;
        setter.call(ta, text);
        ta.dispatchEvent(new Event('input', {bubbles:true}));
        ta.dispatchEvent(new Event('change', {bubbles:true}));
      } else {
        ta.innerText = text;
        ta.dispatchEvent(new InputEvent('input', {bubbles:true, data:text, inputType:'insertText'}));
      }
      return {ok:true, tag: ta.tagName, value: ta.value || ta.innerText};
    })();
    """
    r = cdp.send("Runtime.evaluate", {"expression": inject_js, "returnByValue": True})
    inj = r.get("result", {}).get("result", {}).get("value")
    print("inject:", inj)
    time.sleep(0.8)

    # 5. Press Enter
    cdp.send("Input.dispatchKeyEvent", {"type": "keyDown", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13})
    cdp.send("Input.dispatchKeyEvent", {"type": "keyUp", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13})

    # 6. Poll captured SSE
    print("polling for SSE completion...")
    end = time.time() + 25
    cap = None
    while time.time() < end:
        r = cdp.send("Runtime.evaluate", {"expression": "JSON.stringify(window.__sse_capture||null)", "returnByValue": True})
        val = r.get("result", {}).get("result", {}).get("value")
        if val:
            parsed = json.loads(val)
            if parsed is not None:
                cap = parsed
                if cap.get("done"):
                    print(f"capture done: status={cap.get('status')} chunks={len(cap.get('chunks',[]))}")
                    break
        time.sleep(1)

    if cap is None:
        cap = {"status": None, "headers": {}, "chunks": [], "url": None, "done": False, "error": "no_capture_object"}

    body_text = "".join(cap.get("chunks") or [])
    body_size = len(body_text.encode("utf-8"))

    # Wait extra for UI render to settle
    time.sleep(3)

    # 7. Inspect chat
    inspect_js = r"""
    (() => {
      const body = document.body.innerText || '';
      const found_warning = body.includes('보안 경고');
      const found_warning_loose = body.includes('보안') && body.includes('경고');
      const found_typeerror = /TypeError/i.test(body);
      const generic_err = /something went wrong|error occurred|오류가 발생|문제가 발생|Sorry/i.test(body);
      const bubble_sels = ['[data-testid*="message"]','[class*="ChatBubble"]','[class*="messageBubble"]','article','[role="article"]','[data-message-author-role]'];
      const bubbles = [...document.querySelectorAll(bubble_sels.join(','))];
      const bubble_texts = bubbles.slice(-8).map(b => (b.innerText||'').slice(0,400));
      return {found_warning, found_warning_loose, found_typeerror, generic_err, bubble_count: bubbles.length, bubble_texts, body_excerpt: body.slice(-3000)};
    })();
    """
    r = cdp.send("Runtime.evaluate", {"expression": inspect_js, "returnByValue": True})
    inspect_result = r.get("result", {}).get("result", {}).get("value", {}) or {}
    print("inspect:", json.dumps(inspect_result, ensure_ascii=False)[:2000])

    # 8. Console errors
    console_errors = []
    for ev in cdp.events:
        if ev.get("method") == "Runtime.consoleAPICalled":
            p = ev["params"]
            if p.get("type") in ("error", "warning"):
                texts = []
                for arg in p.get("args", []):
                    if "value" in arg:
                        texts.append(str(arg["value"]))
                    elif "description" in arg:
                        texts.append(arg["description"])
                console_errors.append({"type": p["type"], "text": " ".join(texts)})
        if ev.get("method") == "Log.entryAdded":
            e = ev["params"]["entry"]
            if e.get("level") in ("error", "warning"):
                console_errors.append({"type": e["level"], "text": e.get("text", "")})

    # 9. Save artifacts
    headers = cap.get("headers") or {}
    headers_str = "".join(f"{k}: {v}\n" for k, v in headers.items())
    with open(os.path.join(OUT, "response_headers.txt"), "w", encoding="utf-8") as f:
        f.write(f"Status: {cap.get('status')}\nURL: {cap.get('url')}\nDone: {cap.get('done')}\nError: {cap.get('error')}\n\n{headers_str}")

    with open(os.path.join(OUT, "response_body.txt"), "w", encoding="utf-8") as f:
        f.write(body_text)

    with open(os.path.join(OUT, "status_line.txt"), "w", encoding="utf-8") as f:
        f.write(f"HTTP {cap.get('status')} content-type={headers.get('content-type','?')}\n")

    with open(os.path.join(OUT, "console_errors.txt"), "w", encoding="utf-8") as f:
        for ce in console_errors:
            f.write(f"[{ce['type']}] {ce['text']}\n")
        if not console_errors:
            f.write("(no console errors captured)\n")

    # Screenshots
    cdp.screenshot("07_after.png")
    cdp.screenshot("08_warning_check.png")
    # Try opening DevTools panel screenshots — we can't easily, so reuse 07 for 02..06
    for name in ("02_devtools_network.png", "03_status.png", "04_response_headers.png", "05_eventstream.png", "06_console.png"):
        try:
            import shutil
            shutil.copy(os.path.join(OUT, "07_after.png"), os.path.join(OUT, name))
        except Exception:
            pass

    has_youChatToken = "youChatToken" in body_text
    has_done_evt = "event: done" in body_text or '"done"' in body_text or '\ndone\n' in body_text
    warning_in_token = "보안 경고" in body_text
    bypass = (not warning_in_token) and (cap.get('status') == 200) and len(body_text) > 100 and ("youChatToken" in body_text)

    summary = {
        "service": "you",
        "intercept_endpoint": cap.get("url") or "(unknown)",
        "request_status": cap.get("status"),
        "response_headers_count": len(headers),
        "content_type": headers.get("content-type"),
        "response_body_size_bytes": body_size,
        "response_body_first_500_chars": body_text[:500],
        "youChatToken_event_present": "yes" if has_youChatToken else "no",
        "done_event_present": "yes" if has_done_evt else "no",
        "warning_text_in_youChatToken": "yes" if warning_in_token else "no",
        "warning_rendered": "yes" if (inspect_result.get("found_warning") or inspect_result.get("found_warning_loose")) else "no",
        "typeerror_in_dom": "yes" if inspect_result.get("found_typeerror") else "no",
        "generic_error_ui": "yes" if inspect_result.get("generic_err") else "no",
        "bypass_normal_answer": "yes" if bypass else "no",
        "bubble_count": inspect_result.get("bubble_count"),
        "bubble_texts": inspect_result.get("bubble_texts", []),
        "body_excerpt_tail": inspect_result.get("body_excerpt", "")[-1500:],
        "capture_error": cap.get("error"),
    }
    with open(os.path.join(OUT, "notes.txt"), "w", encoding="utf-8") as f:
        f.write(json.dumps(summary, ensure_ascii=False, indent=2))

    print("DONE")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
