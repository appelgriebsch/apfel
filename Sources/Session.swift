// ============================================================================
// Session.swift — FoundationModels session management and streaming
// Part of apfel — Apple Intelligence from the command line
// SHARED by both CLI and server modes.
// ============================================================================

import FoundationModels
import Foundation

// MARK: - Session Options

/// Options forwarded from CLI flags or OpenAI request parameters.
struct SessionOptions: Sendable {
    let temperature: Double?
    let maxTokens: Int?
    let seed: UInt64?
    let permissive: Bool

    static let defaults = SessionOptions(
        temperature: nil, maxTokens: nil, seed: nil, permissive: false
    )
}

// MARK: - Generation Options

func makeGenerationOptions(_ opts: SessionOptions) -> GenerationOptions {
    let sampling: GenerationOptions.SamplingMode? = opts.seed.map {
        .random(top: 50, seed: $0)
    }
    return GenerationOptions(
        sampling: sampling,
        temperature: opts.temperature,
        maximumResponseTokens: opts.maxTokens
    )
}

// MARK: - Model Selection

func makeModel(permissive: Bool) -> SystemLanguageModel {
    SystemLanguageModel(
        guardrails: permissive ? .permissiveContentTransformations : .default
    )
}

// MARK: - Simple Session (CLI use)

/// Create a LanguageModelSession with optional system instructions for CLI use.
func makeSession(systemPrompt: String?, options: SessionOptions = .defaults) -> LanguageModelSession {
    let model = makeModel(permissive: options.permissive)
    return LanguageModelSession(model: model, instructions: systemPrompt)
}

// MARK: - Streaming Helper

/// Stream a response, optionally printing deltas to stdout.
/// FoundationModels returns cumulative snapshots; we compute deltas by tracking prev length.
/// - Returns: The complete response text after all chunks have been received.
func collectStream(
    _ session: LanguageModelSession,
    prompt: String,
    printDelta: Bool,
    options: GenerationOptions = GenerationOptions()
) async throws -> String {
    let stream = session.streamResponse(to: prompt, options: options)
    var prev = ""
    for try await snapshot in stream {
        let content = snapshot.content
        if content.count > prev.count {
            let idx = content.index(content.startIndex, offsetBy: prev.count)
            let delta = String(content[idx...])
            if printDelta {
                print(delta, terminator: "")
                fflush(stdout)
            }
        }
        prev = content
    }
    return prev
}
