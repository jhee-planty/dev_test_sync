"""Save diagnostic notes + per-step screenshots for human review."""
import json, time, urllib.request, websocket, os, sys, base64
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

OUT = r"C:\Users\최장희\Documents\dev_test_sync\files\634"

# Update notes.txt with deeper finding
with open(os.path.join(OUT, "cdp_network_streamingSearch.json"), "r", encoding="utf-8") as f:
    netdata = json.load(f)

err = None
status = None
content_type = None
url = None
req_headers = None
for r in netdata:
    url = r["url"]
    for ev in r["events"]:
        if ev["method"] == "Network.loadingFailed":
            err = ev.get("errorText")
        if ev["method"] == "Network.responseReceived":
            status = (ev.get("response") or {}).get("status")
        if ev["method"] == "Network.requestWillBeSentExtraInfo":
            req_headers = ev.get("headers")

# Update response_headers.txt
with open(os.path.join(OUT, "response_headers.txt"), "w", encoding="utf-8") as f:
    f.write(f"URL: {url}\n")
    f.write(f"HTTP Status (CDP Network domain): {status}\n")
    f.write(f"Network.loadingFailed errorText: {err}\n")
    f.write(f"\n--- Response Headers ---\n(none — connection closed before response)\n")
    f.write(f"\n--- Request Headers (sent) ---\n")
    if req_headers:
        for k, v in req_headers.items():
            if k.lower() in ("cookie", ":path"):
                f.write(f"{k}: <redacted/long>\n")
            else:
                f.write(f"{k}: {v}\n")

# Update status_line.txt
with open(os.path.join(OUT, "status_line.txt"), "w", encoding="utf-8") as f:
    f.write(f"HTTP Status: {status if status else 'NONE (connection closed)'}\n")
    f.write(f"Network error: {err}\n")

# Write notes.txt summary
notes = {
    "request_id": 634,
    "service": "you",
    "engine_fix_under_test": "Cycle 95 — SSE v3 CRLF fix (envelope_template stored with CHAR(13,10))",
    "wire_level_outcome": "FAIL — net::ERR_CONNECTION_CLOSED",
    "intercept_endpoint": url,
    "request_status": status,
    "network_loadingFailed_error": err,
    "ui_outcome": "Generic error: '🤖 Sorry, something went wrong. Please try again later.' (with Error ID)",
    "warning_rendered_보안경고": False,
    "youChatToken_event_present": False,
    "done_event_present": False,
    "bypass_normal_answer": False,
    "verdict": "FAILED — same wire-level failure as #633. CRLF fix in envelope did NOT resolve the issue. Browser receives 0 bytes; TCP connection closed by APF/proxy before any HTTP response.",
    "delta_vs_633": "SAME (still ERR_CONNECTION_CLOSED, no SSE bytes delivered, generic error UI)",
    "engineering_hypotheses": [
        "Engine convert_to_http2_response may still return size=0 — confirm stored body actually starts with 'HTTP/1.1 200 OK\\r\\n' bytes (not literal backslash-n)",
        "CHAR(13,10) UPDATE may have been applied to wrong row OR template not picked up due to cache/version",
        "HTTP/2 frame emitter may reject body when content-length header missing (chunked SSE) — possibly DATA frame with END_STREAM never sent",
        "Possible TLS-level RST from APF before any HTTP layer kicks in",
    ],
    "recommended_next_steps": [
        "etap log: tcpdump on egress to confirm whether engine sent any HTTP/2 DATA frames or just RST/FIN",
        "DB hex check: SELECT HEX(envelope_template) WHERE service='you' — confirm starts with 485454 (=H'HTTP'), 0D0A appears at correct positions",
        "Compare with copilot/perplexity engine output where similar SSE flow may already work",
    ],
}

with open(os.path.join(OUT, "notes.txt"), "w", encoding="utf-8") as f:
    json.dump(notes, f, ensure_ascii=False, indent=2)

# Now grab a fresh screenshot showing the error state and the DevTools (if open)
tabs = json.loads(urllib.request.urlopen("http://127.0.0.1:9222/json").read())
tab = [t for t in tabs if t.get("type") == "page" and "you.com" in (t.get("url") or "")][0]
ws = websocket.create_connection(tab["webSocketDebuggerUrl"], suppress_origin=True, max_size=200_000_000)
def send(method, params=None):
    msg = {"id": 1, "method": method, "params": params or {}}
    ws.send(json.dumps(msg))
    while True:
        d = json.loads(ws.recv())
        if d.get("id") == 1: return d

# Capture full-page screenshot of you.com showing the error
r = send("Page.captureScreenshot", {"format": "png", "captureBeyondViewport": True})
img_b64 = r.get("result", {}).get("data")
if img_b64:
    with open(os.path.join(OUT, "07_after.png"), "wb") as f:
        f.write(base64.b64decode(img_b64))
    with open(os.path.join(OUT, "08_warning_check.png"), "wb") as f:
        f.write(base64.b64decode(img_b64))
    print("saved 07_after.png + 08_warning_check.png (full page)")

ws.close()
print("ALL ARTIFACTS UPDATED")
