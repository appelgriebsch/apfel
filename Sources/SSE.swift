// ============================================================================
// SSE.swift — Server-Sent Events streaming for OpenAI-compatible responses
// Part of apfel — Apple Intelligence from the command line
// ============================================================================

import Foundation

/// Format a single SSE data line from a ChatCompletionChunk.
/// Returns: "data: {json}\n\n"
func sseDataLine(_ chunk: ChatCompletionChunk) -> String {
    let json = jsonString(chunk, pretty: false)
    return "data: \(json)\n\n"
}

/// The SSE termination marker.
let sseDone = "data: [DONE]\n\n"

/// Create the initial SSE chunk that announces the assistant role.
func sseRoleChunk(id: String, created: Int) -> ChatCompletionChunk {
    ChatCompletionChunk(
        id: id,
        object: "chat.completion.chunk",
        created: created,
        model: modelName,
        choices: [.init(
            index: 0,
            delta: .init(role: "assistant", content: nil),
            finish_reason: nil
        )]
    )
}

/// Create a content delta SSE chunk.
func sseContentChunk(id: String, created: Int, content: String) -> ChatCompletionChunk {
    ChatCompletionChunk(
        id: id,
        object: "chat.completion.chunk",
        created: created,
        model: modelName,
        choices: [.init(
            index: 0,
            delta: .init(role: nil, content: content),
            finish_reason: nil
        )]
    )
}

/// Create the final SSE chunk with finish_reason.
func sseStopChunk(id: String, created: Int) -> ChatCompletionChunk {
    ChatCompletionChunk(
        id: id,
        object: "chat.completion.chunk",
        created: created,
        model: modelName,
        choices: [.init(
            index: 0,
            delta: .init(role: nil, content: nil),
            finish_reason: "stop"
        )]
    )
}
