### Iteration 4 (2026-03-24) — QUIC Bypass 확정

- DB: domain=gemini.google.com, path=/_/BardChatUi/data/batchexecute (id=5, enabled)
- etapd restart 후 gemini detect 0건 (12:15 restart, 12:43 restart 모두)
- etap.log 분석: claude(claude.ai), notion(www.notion.so) 정상 detect, gemini 전무
- 재시작 전: signaler-pa.clients6.google.com만 detect (구 DB 패턴, 시그널링 채널)

**근본 원인**: Gemini은 **HTTP/3 (QUIC)** 사용
- QUIC = UDP 443 + TLS 1.3 (자체 핸드셰이크)
- etap은 TCP 기반 TLS 인터셉션만 지원 → QUIC 트래픽 미감지
- 실제 batchexecute API는 gemini.google.com:443/UDP로 전송

**해결 방안**:
1. **방화벽 UDP 443 차단** (권장): gemini.google.com 대상 UDP 443 차단 → Chrome이 HTTP/2(TCP)로 자동 폴백 → etap 인터셉션 가능
2. 대안: Chrome Enterprise 정책으로 QUIC 비활성화 (--disable-quic)

**Status**: QUIC_BYPASS — 네트워크 정책 변경 필요
