// Hooks installed in browser console during request #965 capture.
// Install order: 1) fetch+WebSocket  2) XHR+EventSource

// === STEP 1 ===
window.__cap = [];
const _f = window.fetch;
window.fetch = async (...a) => {
  const u = typeof a[0] === 'string' ? a[0] : a[0].url;
  const isStream = /chat-agent\/messages|chat\/.*stream|sse/.test(u);
  const r = await _f.apply(this, a);
  if (isStream) {
    const ct = r.headers.get('content-type') || '';
    const c = r.clone();
    const reader = c.body.getReader();
    const dec = new TextDecoder();
    let buf = '', n = 0;
    (async () => {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const t = dec.decode(value);
        buf += t; n++;
        window.__cap.push({ k: 'chunk', n, url: u, ct, len: t.length, head: t.slice(0, 400) });
        if (n < 6) console.log('STREAM#' + n, t.slice(0, 200));
      }
      window.__cap.push({ k: 'end', url: u, total: buf.length, sample: buf.slice(0, 2000) });
      console.log('STREAM_END len=' + buf.length);
    })();
  }
  return r;
};
const _W = window.WebSocket;
window.WebSocket = function (u, p) {
  console.log('WS_OPEN', u);
  const ws = new _W(u, p);
  window.__cap.push({ k: 'ws_open', u });
  ws.addEventListener('message', e => {
    window.__cap.push({ k: 'ws_msg', u, d: String(e.data).slice(0, 400) });
    console.log('WS_MSG', String(e.data).slice(0, 200));
  });
  return ws;
};
Object.setPrototypeOf(window.WebSocket, _W);
window.WebSocket.prototype = _W.prototype;

// === STEP 2 (XHR + EventSource) ===
const _o = XMLHttpRequest.prototype.open;
const _s = XMLHttpRequest.prototype.send;
XMLHttpRequest.prototype.open = function (m, u) { this.__u = u; this.__m = m; return _o.apply(this, arguments); };
XMLHttpRequest.prototype.send = function (b) {
  const xhr = this;
  const u = xhr.__u || '';
  if (/api\.wrtn|chat-agent|chat\//.test(u)) {
    console.log('XHR_OPEN', xhr.__m, u);
    xhr.addEventListener('progress', e => {
      const t = xhr.responseText || '';
      window.__cap.push({ k: 'xhr_p', u, len: t.length, head: t.slice(Math.max(0, t.length - 400)) });
    });
    xhr.addEventListener('load', e => {
      const t = xhr.responseText || '';
      window.__cap.push({ k: 'xhr_load', u, status: xhr.status, ct: xhr.getResponseHeader('content-type'), len: t.length, sample: t.slice(0, 2000), tail: t.slice(-1000) });
      console.log('XHR_LOAD', u, 'status', xhr.status, 'ct', xhr.getResponseHeader('content-type'), 'len', t.length);
    });
  }
  return _s.apply(this, arguments);
};
const _ES = window.EventSource;
if (_ES) {
  window.EventSource = function (u, o) {
    console.log('SSE_OPEN', u);
    const es = new _ES(u, o);
    window.__cap.push({ k: 'sse_open', u });
    es.addEventListener('message', e => {
      window.__cap.push({ k: 'sse_msg', u, d: String(e.data).slice(0, 400) });
    });
    return es;
  };
  Object.setPrototypeOf(window.EventSource, _ES);
  window.EventSource.prototype = _ES.prototype;
}
