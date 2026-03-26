# Implementation Status — Apfel Golden Goals

**Last Updated:** 2026-03-26
**Agent:** Claude Sonnet 4.6 (claude-sonnet-4-6)
**Session started from:** `~/dev/temp/apfel-feedback.md` briefing

---

## What Was Done

### Phase 1 — Package.swift restructure + TokenCounter ✅
- Restructured `Package.swift` with 3 targets: `apfel` (executable), `ApfelCore` (library, no FoundationModels dep), `apfel-tests` (executable test runner)
- `ApfelCore` library (`Sources/Core/`) is pure Swift — can be tested without Xcode/XCTest
- `TokenCounter.swift` implemented with `chars/4` approximation + upgrade path documented (real API requires macOS 26.4 SDK → TICKET-001)
- Custom test runner (`Tests/apfelTests/main.swift`) avoids XCTest/Swift Testing framework dependency — runs with `swift run apfel-tests`

### Phase 2 — ApfelError typed errors ✅ (TDD, 9 tests passing)
- `Sources/Core/ApfelError.swift` — public typed error enum: `.guardrailViolation`, `.contextOverflow`, `.rateLimited`, `.concurrentRequest`, `.unsupportedLanguage`, `.unknown`
- `ApfelError.classify(_ error: Error) -> ApfelError` — keyword matching on `localizedDescription`
- `cliLabel`, `openAIType`, `openAIMessage` properties for correct error formatting in both CLI and server modes
- Unit tests: `Tests/apfelTests/ApfelErrorTests.swift` (9 tests)

### Phase 3 — ToolCallHandler ✅ (TDD, 12 tests passing)
- `Sources/Core/ToolCallHandler.swift` — pure logic, no FoundationModels dependency
- `buildSystemPrompt(tools:)` — injects tool definitions into session instructions as JSON schema descriptions
- `detectToolCall(in:)` — detects `{"tool_calls":[...]}` JSON in model output (handles clean JSON, markdown code blocks, JSON after preamble text)
- `formatToolResult(callId:name:content:)` — formats tool result for history injection
- Unit tests: `Tests/apfelTests/ToolCallHandlerTests.swift` (12 tests)

### Phase 4 — Models + ToolModels + Session options ✅
- **`Sources/Models.swift`** fully rewritten:
  - `OpenAIMessage` now has `tool_calls: [ToolCall]?`, `tool_call_id: String?`, `name: String?`
  - `MessageContent` enum: `.text(String)` / `.parts([ContentPart])` — handles both string and array content
  - `ContentPart` with image_url detection
  - `ChatCompletionRequest` extended: `seed`, `tools`, `tool_choice`, `response_format`, `logprobs`, `n`, `user`
  - `ChatCompletionChunk.Delta` extended with `tool_calls: [ToolCall]?`
  - `ModelsListResponse.ModelObject` extended: `context_window`, `supported_parameters`, `unsupported_parameters`, `notes`
- **`Sources/ToolModels.swift`** created: `OpenAITool`, `OpenAIFunction`, `RawJSON`, `ToolCall`, `ToolCallFunction`, `ToolChoice`, `ResponseFormat`, `AnyCodable`
- **`Sources/Session.swift`** rewritten: `SessionOptions` struct, `makeGenerationOptions()`, `makeModel(permissive:)`, wired `GenerationOptions(sampling:temperature:maximumResponseTokens:)` (confirmed in 26.1 SDK)
- **`Sources/SSE.swift`** fixed: added `tool_calls: nil` to all Delta inits

### Phase 5 — ContextManager + Handler rewrite ✅
- **`Sources/ContextManager.swift`** created:
  - Uses real Transcript API (confirmed available in 26.1 SDK): `LanguageModelSession(model:transcript:)`, `Transcript(entries:)`, `Transcript.Entry.instructions/prompt/response/toolOutput`
  - Converts OpenAI stateless message history into a stateful `LanguageModelSession` without re-running inference on history (fixes the **critical history replay bug**)
  - Handles system prompt → `Transcript.Instructions`
  - Handles user messages → `Transcript.Prompt` (with `GenerationOptions`)
  - Handles assistant messages → `Transcript.Response`
  - Handles tool result messages → `Transcript.ToolOutput`
  - Injects tool definitions via `ToolCallHandler.buildSystemPrompt()` into instructions
  - Applies `permissiveContentTransformations` guardrails via `makeModel(permissive:)`
- **`Sources/Handlers.swift`** fully rewritten:
  - Uses `ContextManager.makeSession()` — no more `session.respond()` on history
  - Image content rejection (400 Bad Request)
  - `SessionOptions` extracted from request `temperature`/`seed`/`max_tokens`
  - `GenerationOptions` passed to both `session.respond()` and `session.streamResponse()`
  - Tool call detection: `ToolCallHandler.detectToolCall()` → `finish_reason: "tool_calls"` when detected
  - Proper `OpenAIMessage(content: .text(content))` for assistant responses
  - Correct `ModelsListResponse.ModelObject` with full capabilities metadata

**All 21 unit tests pass.** `swift build` clean.

---

## What Is NOT Done (Open Tickets)

| Ticket | Description | Priority | Blocker |
|--------|-------------|----------|---------|
| [TICKET-001](TICKET-001-token-counting-api.md) | Real token counting via `tokenCount(for:)` | P1 | macOS 26.4 SDK |
| [TICKET-002](TICKET-002-context-window-truncation.md) | Context window overflow protection | P0 | Needs real token counts (TICKET-001) + implementation |
| [TICKET-003](TICKET-003-cli-polish.md) | CLI flags: `--temperature`, `--seed`, `--max-tokens`, `--permissive`, `--tokens`, `--model-info`; env vars; chat context rotation | P1 | Ready to implement |
| [TICKET-004](TICKET-004-server-polish.md) | Server: `/v1/completions` 501, `/v1/embeddings` 501, OPTIONS CORS, enhanced `/health` | P1 | Ready to implement |
| [TICKET-005](TICKET-005-integration-tests.md) | Python openai client E2E integration tests | P1 | Needs TICKET-003+004 first |

---

## Why Certain Things Were Not Implemented

### Token counting API (`tokenCount(for:)`)
**API confirmed NOT in 26.1 SDK.** Verified by inspecting the actual `.swiftinterface` file:
```
/Library/Developer/CommandLineTools/SDKs/MacOSX26.1.sdk/System/Library/Frameworks/FoundationModels.framework
```
The method does not exist in the ARM64 macOS interface. TICKET-001 documents the exact upgrade path.

### Context window truncation
Cannot implement correctly without real token counts. With `chars/4` approximation, any
truncation decision would be unreliable (could truncate too early or not enough). Documented
in TICKET-002 with the implementation algorithm ready to paste in when TICKET-001 is done.

### CLI flags (`--temperature`, etc.)
`SessionOptions` struct and `makeGenerationOptions()` are both fully implemented — the
wiring from `main.swift` argument parsing into the session is the missing piece. This is
straightforward work with no blockers (TICKET-003).

### Server endpoints (`/v1/completions`, CORS)
Clean `Server.swift` additions with no blockers. Documented in TICKET-004.

### Integration tests
Require the server to be running, so cannot be automated in CI without the full build.
Documented in TICKET-005 with all test cases written and ready to run.

---

## Architecture Decisions Made

**Transcript API vs. text injection for history:**
Used the real `Transcript` API (`.instructions`, `.prompt`, `.response`, `.toolOutput`) instead
of formatting history as text inside the system prompt. The Transcript approach is semantically
correct — the model sees proper session structure rather than a long text blob. Verified API
availability in 26.1 swiftinterface before implementing.

**Tool calling via prompt injection + JSON detection:**
Apple's `Tool` protocol requires compile-time types and auto-executes tools server-side —
completely incompatible with OpenAI's client-side execution model. Chose system-prompt injection
+ JSON output detection (`ToolCallHandler`). This is the only viable approach without
modifying the client protocol.

**ApfelCore as a separate library target:**
Moved `ApfelError` and `ToolCallHandler` to `Sources/Core/` as a library target (`ApfelCore`)
with no `FoundationModels` dependency. This allows unit testing without Apple Silicon / macOS 26
and keeps pure logic testable in isolation.

**Custom test runner:**
`XCTest` and Swift `Testing` framework both require Xcode installation (not just CommandLineTools).
Built a minimal custom runner (`apfel-tests` executable target) that runs with `swift run apfel-tests`.
