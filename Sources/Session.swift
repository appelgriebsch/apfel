// ============================================================================
// Session.swift — FoundationModels session management and streaming
// Part of apfel — Apple Intelligence from the command line
// SHARED by both CLI and server modes.
// ============================================================================

import FoundationModels
import Foundation

/// Create a LanguageModelSession with optional system instructions.
/// The session maintains conversation history for multi-turn chat.
func makeSession(systemPrompt: String?) -> LanguageModelSession {
    if let sys = systemPrompt {
        return LanguageModelSession(instructions: sys)
    }
    return LanguageModelSession()
}

/// Stream a response from the model, optionally printing deltas to stdout.
///
/// FoundationModels returns cumulative snapshots (each snapshot contains the full
/// response so far), so we compute deltas by tracking the previous content length.
///
/// - Parameters:
///   - session: The language model session to use
///   - prompt: The user's input text
///   - printDelta: If true, print each new chunk to stdout as it arrives.
///                 Set to false when buffering for JSON output.
/// - Returns: The complete response text after all chunks have been received.
func collectStream(
    _ session: LanguageModelSession,
    prompt: String,
    printDelta: Bool
) async throws -> String {
    let response = session.streamResponse(to: prompt)
    var prev = ""
    for try await snapshot in response {
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
