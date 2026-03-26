# TICKET-003: CLI Polish — Flags, Chat Context Rotation, Error Labels

**Status:** Open
**Priority:** P1 (usability, "perfect Unix tool" goal)
**Blocked by:** Nothing — all APIs available

---

## Changes Needed

### 1. `main.swift` — New flags

Add to argument parsing:
```
--temperature <float>   Sampling temperature (0.0–2.0). Default: model default.
--seed <int>            Random seed for reproducible output.
--max-tokens <int>      Maximum response tokens. Default: model default.
--permissive            Use .permissiveContentTransformations guardrails.
--tokens                Show token counts in output (uses TokenCounter).
--model-info            Print model availability, context size, capabilities.
--json                  Output as JSON (existing flag, ensure it includes usage).
--system <string>       System prompt (alternative to piped system message).
```

Environment variable support:
```
APFEL_SYSTEM_PROMPT     Default system prompt for all requests
APFEL_HOST              Server host (default: 127.0.0.1)
APFEL_PORT              Server port (default: 11434)
```

### 2. `CLI.swift` — Chat sliding window

The `--chat` mode currently crashes after ~5-6 turns due to context overflow.

Fix: maintain a `messages: [String]` array and rotate out oldest messages when
`estimatedTokens > 3000`. Use `TokenCounter.shared.count()` to estimate.

```swift
// In chat loop, before each turn:
while await estimatedTurnsTokens(messages) > 3000 {
    messages.removeFirst(2)  // remove oldest user+assistant pair
    fputs("[Context rotated: oldest messages dropped]\n", stderr)
}
```

### 3. Error output — typed labels

When a FoundationModels error occurs in CLI mode, prepend the `ApfelError.cliLabel`:

```
[guardrail] The model declined to answer due to content policy.
[context overflow] Message history too long. Use --chat to auto-rotate.
[rate limited] Apple's on-device model is currently busy. Retry in a moment.
```

Currently all errors print as `Error: <raw localizedDescription>`.

### 4. `--model-info` output

```
Model: apple/on-device-3b
Available: true
Context window: 4096 tokens (approximate, TICKET-001 for real count)
Supported: temperature, seed, max_tokens, streaming, tools
```

## Verification

```bash
echo "2+2?" | .build/release/apfel --temperature 0 --seed 42
echo "2+2?" | .build/release/apfel --tokens
.build/release/apfel --model-info
.build/release/apfel --permissive "Write something edgy"
APFEL_SYSTEM_PROMPT="You are a pirate" echo "Hello" | .build/release/apfel
.build/release/apfel --chat --tokens  # verify 20+ turns without crash
```
