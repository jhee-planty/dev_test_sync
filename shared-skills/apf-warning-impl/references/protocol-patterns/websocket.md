# WebSocket (RFC 6455) Pattern

## Mechanism
- HTTP Upgrade: websocket → bidirectional binary/text frames
- Frame structure: FIN/RSV/opcode/MASK/length/payload
- Client→server frames: masked. Server→client: unmasked.
- Sub-protocols: signalR (Microsoft), Connect-RPC (kimi)

## Engine emit
- `on_upgraded_data` hook → APF engine intercepts WS frames after upgrade
- `[APF:ws_upgrade]` (upgrade detected) + `[APF:ws_blocked]` (PII frame blocked)
- Frame consumption alone sufficient for S2 protection (close-frame emit not required, 53차 architectural correction copilot)

## Envelope schema requirements (general)
- Service-specific frame body schema (signalR: type=1 invocation / Connect-RPC: protobuf-like)
- Engine emits replacement frame OR consumes original (depends on strategy)

## Common pitfalls (47-56차 evidence)
- **Frame masking**: client→server 만 masked. Engine 이 server→client 방향 inject 시 unmasked.
- **Schema mismatch**: signalR parser silent-discards raw text frame (copilot Chathub case)
- **Bundle hardening**: SPA bundle 이 frame body 의 새 required fields 검증 (character add_turn: candidates[].editor / chat_info.type / is_final)
- **HAR groundtruth required**: WS frame body sanitization extract 후 schema delta identify

## Verify path
- T1 (engine_fire): `[APF:ws_blocked]` event count
- T2 (UI_render): test PC verdict + frame inject 후 SPA render
- T3 (verify_path): per-service operational state

## Cross-reference
- character: `apf-operation/services/character/` (add_turn schema)
- kimi: `apf-operation/services/kimi/` (Connect-RPC, login required)
- copilot: `apf-operation/services/m365_copilot/` (signalR Chathub)
