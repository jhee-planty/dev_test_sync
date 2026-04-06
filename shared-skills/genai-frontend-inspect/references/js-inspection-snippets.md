# JS Inspection Snippets (Chrome MCP 환경용)

dev PC에서 Chrome MCP(`javascript_tool`)를 사용할 수 있는 환경에서만 실행 가능하다.
test PC에서는 이 코드를 직접 실행할 수 없다. 대신 SKILL.md의 PowerShell 기반 흐름을 따른다.

---

## Baseline DOM Capture

```javascript
// javascript_tool: capture baseline DOM structure
(() => {
  const main = document.querySelector('main') || document.body;
  return {
    title: document.title,
    url: window.location.href,
    mainElementTag: main.tagName,
    childCount: main.children.length,
    messageContainers: document.querySelectorAll(
      '[class*="message"], [class*="chat"], [class*="conversation"]'
    ).length
  };
})()
```

Full DOM snapshot:

```javascript
// javascript_tool: capture full DOM
document.documentElement.outerHTML
```

---

## JS Framework Detection

```javascript
// javascript_tool: detect frameworks
(() => {
  const result = {};
  // React
  const reactEl = document.querySelector('[data-reactroot]') ||
    [...document.querySelectorAll('*')].find(el => Object.keys(el).some(k => k.startsWith('__reactFiber')));
  result.react = !!reactEl;

  // Vue
  result.vue = !!document.querySelector('[data-v-]') ||
    [...document.querySelectorAll('*')].some(el => el.__vue__ || el.__vue_app__);

  // Angular
  result.angular = !!document.querySelector('[ng-version]') || !!window.ng;

  // Next.js
  result.nextjs = !!document.querySelector('#__next');

  // Svelte
  result.svelte = [...document.querySelectorAll('*')].some(el =>
    Object.keys(el).some(k => k.startsWith('__svelte')));

  // Streaming detection
  result.hasEventSource = typeof EventSource !== 'undefined';
  result.hasWebSocket = typeof WebSocket !== 'undefined';
  result.hasFetchStreaming = typeof ReadableStream !== 'undefined';

  return result;
})()
```

---

## Response Container Analysis

프롬프트 전송 후 응답이 렌더링된 상태에서 실행:

```javascript
// javascript_tool: analyze response containers
(() => {
  const containers = document.querySelectorAll('[class*="message"], [class*="response"], [class*="answer"]');
  return Array.from(containers).slice(-3).map(el => ({
    tag: el.tagName,
    className: el.className,
    textLength: el.textContent.length,
    childCount: el.children.length
  }));
})()
```
