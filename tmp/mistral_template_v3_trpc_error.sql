UPDATE ai_prompt_response_templates SET envelope_template = CONCAT(
'HTTP/1.1 200 OK\nContent-Type: application/json\nCache-Control: no-cache\naccess-control-allow-origin: https://chat.mistral.ai\naccess-control-allow-credentials: true\nstrict-transport-security: max-age=15552000; includeSubDomains; preload\nx-content-type-options: nosniff\nx-frame-options: DENY\nvary: Origin\n\n',
'[{"error":{"message":"{{MESSAGE}}","code":-32600,"data":{"code":"BAD_REQUEST","httpStatus":400,"path":"message.newChat"}}}]'
) WHERE id = 24;
