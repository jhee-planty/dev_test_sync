# signalR (Microsoft Chathub) Pattern

## Mechanism
- Microsoft signalR over WebSocket
- Hub messages: `{type: 1, target: "...", arguments: [...]}` invocation form
- Connection negotiation via `/negotiate` endpoint first
- Chathub service: `substrate.office.com` 등 Microsoft 365 services

## Engine emit
- on_upgraded_data hook (WebSocket layer) — see [websocket.md](websocket.md)
- `[APF:ws_blocked]` for blocked frames

## Envelope schema requirements (Chathub specific)
- Hub message JSON envelope (signalR protocol)
- Chathub-specific fields: cvId / messageId / type 등 reverse-engineering required (HAR audit)
- Raw RFC 6455 text frame = silent-discard (53차 evidence — copilot)

## Common pitfalls (47-56차 evidence — copilot)
- **Auth required**: M365 logged-in session 필수. login.microsoftonline.com OAuth2 flow.
- **Service name mismatch**: DB key = `m365_copilot` (NOT `copilot`)
- **Schema reverse-engineering**: HAR-dependent — Chathub envelope schema 가 비공개, HAR audit 후만 alignment 가능
- **CORS Origin handling**: V8-A CORS Origin fix (48차)
- **S2 protection**: engine frame consumption 만으로 sufficient (close-frame emit 안 해도 OK, 53차 architectural correction)

## Verify path
- T1: `[APF:block_response]` event for substrate.office.com WS frames
- T2: M365 authenticated session 의무 (M4 user-required)
- T3: `apf-operation/services/m365_copilot/` per-service analysis

## Cross-reference
- copilot (m365): `apf-operation/services/m365_copilot/`
- General WebSocket: [websocket.md](websocket.md)
