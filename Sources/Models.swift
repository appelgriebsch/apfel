// ============================================================================
// Models.swift — Data types for CLI and API responses
// Part of apfel — Apple Intelligence from the command line
// ============================================================================

import Foundation

// MARK: - CLI Response Types

/// JSON response for single-prompt CLI mode.
struct ApfelResponse: Encodable {
    let model: String
    let content: String
    let metadata: Metadata

    struct Metadata: Encodable {
        let onDevice: Bool
        let version: String

        enum CodingKeys: String, CodingKey {
            case onDevice = "on_device"
            case version
        }
    }
}

/// JSON message for chat JSONL output (CLI mode).
struct ChatMessage: Encodable {
    let role: String
    let content: String
    let model: String?
}

// MARK: - OpenAI API Types

/// OpenAI chat completion request (POST /v1/chat/completions).
struct ChatCompletionRequest: Decodable, Sendable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool?
    let temperature: Double?
    let max_tokens: Int?
}

/// A single message in the OpenAI messages array.
struct OpenAIMessage: Codable, Sendable {
    let role: String
    let content: String
}

/// OpenAI non-streaming chat completion response.
struct ChatCompletionResponse: Encodable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage

    struct Choice: Encodable, Sendable {
        let index: Int
        let message: OpenAIMessage
        let finish_reason: String
    }

    struct Usage: Encodable, Sendable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
}

/// OpenAI streaming chunk (SSE).
struct ChatCompletionChunk: Encodable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChunkChoice]

    struct ChunkChoice: Encodable, Sendable {
        let index: Int
        let delta: Delta
        let finish_reason: String?
    }

    struct Delta: Encodable, Sendable {
        let role: String?
        let content: String?
    }
}

/// OpenAI error response format.
struct OpenAIErrorResponse: Encodable, Sendable {
    let error: ErrorDetail

    struct ErrorDetail: Encodable, Sendable {
        let message: String
        let type: String
        let param: String?
        let code: String?
    }
}

/// OpenAI models list response.
struct ModelsListResponse: Encodable, Sendable {
    let object: String
    let data: [ModelObject]

    struct ModelObject: Encodable, Sendable {
        let id: String
        let object: String
        let created: Int
        let owned_by: String
    }
}

// MARK: - Token Estimation

/// Rough token estimate: characters / 4 (standard approximation).
/// FoundationModels doesn't expose actual token counts.
func estimateTokens(_ text: String) -> Int {
    max(1, text.count / 4)
}
