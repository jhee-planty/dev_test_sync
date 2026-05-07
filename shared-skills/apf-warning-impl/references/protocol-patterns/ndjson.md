# NDJSON multi-stage Pattern

## Mechanism
- Newline-delimited JSON: each line = standalone JSON object
- Streaming-friendly (parse as stream)
- Multi-stage workflow: each stage = JSON object on separate line
- Sometimes compressed (zstd / gzip / brotli)

## Engine emit
- `on_http2_response_data` (similar to SSE)
- `[APF:block_response]` when PII detected in stream

## Envelope schema requirements (general)
- Each line = valid JSON object
- Multi-stage: ordered stages (e.g., started → running → applied)
- Compression: Content-Encoding handling

## Common pitfalls (47-56차 evidence — notion)
- **Multi-tool-call sequence**: notion 의 NDJSON 이 multiple tool-call stages (started/running/applied 3-line minimum)
- **zstd handling**: Content-Encoding: zstd → engine 의 decompression 필요 (V6-A multi-stage envelope, 48차)
- **page_inject_h2 path**: SSR document response 가 multi-stage envelope 와 다른 path — V6-D/V6-E case (48차 #707/#716/#719/#720 incidents)
- **Reload behavior**: hard reload 시 SSR HTML returned (synthetic NDJSON envelope override 안 됨)

## Verify path
- T1: production log for notion endpoints
- T2: test PC + reload step verify
- T3: `apf-operation/services/notion/` per-service analysis

## Cross-reference
- notion: `apf-operation/services/notion/` (V6-A multi-stage envelope progression)
