# TICKET-004: Server Polish — Missing Endpoints, CORS, Enhanced Health

**Status:** Open
**Priority:** P1 (OpenAI compatibility goal)
**Blocked by:** Nothing — all APIs available

---

## Changes Needed

### 1. `Server.swift` — Missing OpenAI endpoints (501 stubs)

Clients that auto-discover endpoints (LiteLLM, OpenRouter) will 404 if these are missing:

```swift
// POST /v1/completions — text completion (not chat), return 501
router.post("/v1/completions") { _, _ -> Response in
    return openAIError(status: .notImplemented,
        message: "Text completions not supported. Use /v1/chat/completions.",
        type: "not_supported_error")
}

// POST /v1/embeddings — return 501
router.post("/v1/embeddings") { _, _ -> Response in
    return openAIError(status: .notImplemented,
        message: "Embeddings not supported by the Apple on-device model.",
        type: "not_supported_error")
}
```

### 2. CORS Preflight — OPTIONS handler

Browser-based clients (Open WebUI, LibreChat) send OPTIONS preflight:

```swift
router.on(.OPTIONS, "/v1/**") { _, _ -> Response in
    var headers = HTTPFields()
    headers[.accessControlAllowOrigin] = "*"
    headers[.accessControlAllowMethods] = "GET, POST, OPTIONS"
    headers[.accessControlAllowHeaders] = "Content-Type, Authorization"
    return Response(status: .ok, headers: headers)
}
```

### 3. Enhanced `/health` endpoint

Return more detail for load balancer and monitoring checks:

```json
{
  "status": "ok",
  "model": "apple/on-device-3b",
  "version": "0.4.0",
  "context_window": 4096,
  "active_requests": 0,
  "max_concurrent": 4
}
```

### 4. Enhanced `/v1/models` response

The `ModelsListResponse.ModelObject` already has `context_window`, `supported_parameters`,
etc. from the Phase 4 rewrite. Just ensure it's wired into the `/v1/models` endpoint
in `Server.swift` — currently using the old minimal init (see line 49, fixed in Phase 4).

### 5. Authorization header handling

Many clients send `Authorization: Bearer <key>`. The server should accept and ignore it
(Apple's model is local, no auth needed) rather than returning 401.

```swift
// In handleChatCompletion: ignore Authorization header gracefully
```

## Verification

```bash
.build/release/apfel --serve &
curl http://localhost:11434/v1/completions -X POST -H "Content-Type: application/json" -d '{}' | jq .error.type
# → "not_supported_error"

curl -X OPTIONS http://localhost:11434/v1/chat/completions -I
# → 200 OK with CORS headers

curl http://localhost:11434/health | jq .
# → full status JSON with context_window

curl http://localhost:11434/v1/models | jq .data[0].context_window
# → 4096
```
