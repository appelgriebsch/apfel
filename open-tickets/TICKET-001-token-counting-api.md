# TICKET-001: Real Token Counting via Apple API

**Status:** Open
**Priority:** P1 (affects usage accuracy, context management)
**Blocked by:** macOS 26.4 SDK
**Current workaround:** `chars / 4` approximation in `Sources/TokenCounter.swift`

---

## Problem

The `usage` object in every OpenAI chat completion response contains fake token counts:
```json
{"prompt_tokens": 42, "completion_tokens": 87, "total_tokens": 129}
```
These are computed as `text.count / 4` which is ~25% accurate at best.

Clients that gate on token counts (LangChain, OpenAI client libraries with context window management) will see wrong numbers, causing either premature truncation or unexpected overflow.

## Root Cause

`SystemLanguageModel.default.tokenCount(for:)` and `SystemLanguageModel.default.contextSize` require **macOS 26.4 SDK** and are NOT present in the 26.1 SDK installed on this machine.

```bash
# To verify SDK version:
xcrun --show-sdk-version
# → 26.1 (missing tokenCount API)
```

## Upgrade Path

When macOS 26.4 SDK is available, replace `Sources/TokenCounter.swift` with:

```swift
actor TokenCounter {
    static let shared = TokenCounter()

    func count(_ text: String) async -> Int {
        guard !text.isEmpty else { return 0 }
        return (try? await SystemLanguageModel.default.tokenCount(for: text)) ?? max(1, text.count / 4)
    }

    func contextSize() async -> Int {
        return await SystemLanguageModel.default.contextSize
    }
}
```

And update `ContextManager.swift` to use real token counts for truncation decisions.

## Impact

- `usage.prompt_tokens` / `usage.completion_tokens` / `usage.total_tokens` are wrong
- Context window management in `ContextManager.swift` uses `chars/4` as proxy (see `TICKET-003`)
- Clients relying on accurate token counts will get wrong results

## Verification

After SDK upgrade, run:
```bash
swift run apfel-tests  # unit tests must still pass
.build/release/apfel "Hello world" --json  # check usage tokens are non-trivially different from chars/4
```
