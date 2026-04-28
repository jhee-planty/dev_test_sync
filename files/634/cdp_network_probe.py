"""Probe Network domain to capture exact failure code for /api/streamingSearch (round 2)."""
import json, time, urllib.request, websocket, os, sys, threading
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

OUT = r"C:\Users\최장희\Documents\dev_test_sync\files\634"
PROMPT = "내 주민등록번호는 880101-1234567 인데 이걸로 무엇을 알 수 있어?"

tabs = json.loads(urllib.request.urlopen("http://127.0.0.1:9222/json").read())
tab = [t for t in tabs if t.get("type") == "page" and "you.com" in (t.get("url") or "")][0]
print("tab:", tab["url"])
ws = websocket.create_connection(tab["webSocketDebuggerUrl"], suppress_origin=True, max_size=200_000_000)

_id = 0
events = []
lock = threading.Lock()

def send(method, params=None):
    global _id
    _id += 1
    mid = _id
    ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        d = json.loads(ws.recv())
        if d.get("id") == mid:
            return d
        if "method" in d:
            with lock:
                events.append(d)

def drain(seconds):
    end = time.time() + seconds
    while time.time() < end:
        ws.settimeout(0.5)
        try:
            d = json.loads(ws.recv())
            if "method" in d:
                with lock:
                    events.append(d)
        except Exception:
            pass
    ws.settimeout(None)

send("Network.enable", {"maxTotalBufferSize": 50_000_000, "maxResourceBufferSize": 20_000_000})
send("Page.enable")
send("Runtime.enable")

# Navigate to a fresh chat
send("Page.navigate", {"url": "https://you.com/?chatMode=default"})
time.sleep(8)

# Inject prompt + submit
inject_js = r"""
(()=>{
  const el = [...document.querySelectorAll('textarea,[contenteditable=true]')].filter(e=>e.offsetParent!==null)[0];
  if (!el) return {ok:false, reason:'noTA'};
  el.focus();
  const text = "내 주민등록번호는 880101-1234567 인데 이걸로 무엇을 알 수 있어?";
  if (el.tagName==='TEXTAREA' || el.tagName==='INPUT') {
    const setter = Object.getOwnPropertyDescriptor(el.__proto__, 'value').set;
    setter.call(el, text);
    el.dispatchEvent(new Event('input', {bubbles:true}));
  } else {
    el.innerText = text;
    el.dispatchEvent(new InputEvent('input',{bubbles:true,data:text,inputType:'insertText'}));
  }
  return {ok:true, tag: el.tagName};
})()
"""
r = send("Runtime.evaluate", {"expression": inject_js, "returnByValue": True})
print("inject:", r.get("result", {}).get("result", {}).get("value"))
time.sleep(0.6)

send("Input.dispatchKeyEvent", {"type":"keyDown","key":"Enter","code":"Enter","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13})
send("Input.dispatchKeyEvent", {"type":"keyUp","key":"Enter","code":"Enter","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13})

print("draining 30s for network events...")
drain(30)

# Filter
target_reqs = {}
for ev in events:
    m = ev.get("method")
    p = ev.get("params") or {}
    rid = p.get("requestId")
    if m == "Network.requestWillBeSent":
        u = (p.get("request") or {}).get("url","")
        if "/api/streamingSearch" in u:
            target_reqs[rid] = {"url": u, "events": []}
    if rid in target_reqs:
        target_reqs[rid]["events"].append({"method": m, "params": p})

out = []
for rid, info in target_reqs.items():
    out.append({"requestId": rid, "url": info["url"][:200], "events": [
        {"method": e["method"], **{k: e["params"].get(k) for k in ("type","errorText","canceled","blockedReason","corsErrorStatus","status","statusText","headers","mimeType","fromCache","fromServiceWorker","timing","response")} } for e in info["events"]
    ]})

with open(os.path.join(OUT, "cdp_network_streamingSearch.json"), "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2, default=str)

for r in out:
    print("\n=== REQUEST", r["requestId"], r["url"][:120])
    for e in r["events"]:
        keys = {k:v for k,v in e.items() if v is not None and k != "method"}
        print(" ", e["method"], json.dumps(keys, ensure_ascii=False, default=str)[:600])

ws.close()
print("\nSAVED:", os.path.join(OUT, "cdp_network_streamingSearch.json"))
