# TICKET-002: Context Window Overflow Protection

**Status:** Open
**Priority:** P0 (crash / silent corruption in production)
**Blocked by:** TICKET-001 (real token counts needed for accurate truncation)
**Current workaround:** None — overflow causes FoundationModels to throw, session dies

---

## Problem

Apple's on-device model has a **4096 token context window**. If the combined size of
history + system prompt + final user message exceeds this limit, `session.respond()`
throws a `LanguageModelSession.GenerationError.contextLengthExceeded` error.

In the OpenAI API, clients send full message history every request. A 20-turn
conversation can easily exceed 4096 tokens, causing the server to return a 500 error
instead of gracefully truncating and continuing.

## Root Cause

`ContextManager.makeSession()` currently passes ALL history into the Transcript without
checking total token count. We need to:

1. Count tokens in instructions + each history entry
2. Evict oldest messages (keeping system prompt + recent messages) until within budget
3. Return the truncated session (model continues from available context)

## Implementation Plan

In `Sources/ContextManager.swift`, add truncation before building the Transcript:

```swift
// After building `entries`, check total tokens
let budget = await TokenCounter.shared.inputBudget(reservedForOutput: 512)

// Sum tokens for all entries
var tokenCount = 0
var truncatedEntries: [Transcript.Entry] = []

// Always keep instructions
if let instrEntry = entries.first, case .instructions = instrEntry {
    tokenCount += await TokenCounter.shared.count(instrEntry.description)
    truncatedEntries.append(instrEntry)
}

// Add history entries newest-first until budget fills
for entry in entries.dropFirst().reversed() {
    let entryTokens = await TokenCounter.shared.count(entry.description)
    if tokenCount + entryTokens < budget {
        tokenCount += entryTokens
        truncatedEntries.insert(entry, at: truncatedEntries.endIndex - 0)  // maintain order
    }
    // else: skip (oldest messages evicted)
}
```

**Requires:** TICKET-001 for accurate token counts. With chars/4 approximation, truncation
threshold should be set conservatively (e.g., 3000 tokens budget).

## Verification

```bash
# Start server
.build/release/apfel --serve &

# Send 25+ turn conversation
python3 Tests/integration/test_context_overflow.py
# Should: gracefully truncate and continue (not 500)
```
