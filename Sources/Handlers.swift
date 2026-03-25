// ============================================================================
// Handlers.swift — HTTP request handlers for OpenAI-compatible API
// Part of apfel — Apple Intelligence from the command line
// ============================================================================

import FoundationModels
import Foundation
import Hummingbird
import NIOCore

// MARK: - /v1/models

/// GET /v1/models — List available models (static response).
func handleListModels() -> Response {
    let response = ModelsListResponse(
        object: "list",
        data: [.init(
            id: modelName,
            object: "model",
            created: 1719792000,
            owned_by: "apple"
        )]
    )
    let body = jsonString(response)
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: ByteBuffer(string: body))
    )
}

// MARK: - /v1/chat/completions

/// POST /v1/chat/completions — Main chat endpoint (streaming + non-streaming).
func handleChatCompletion(_ request: Request, context: some RequestContext) async throws -> Response {
    // Decode request body
    let body = try await request.body.collect(upTo: 1024 * 1024)  // 1MB max
    let decoder = JSONDecoder()
    let chatRequest: ChatCompletionRequest
    do {
        chatRequest = try decoder.decode(ChatCompletionRequest.self, from: body)
    } catch {
        return openAIError(
            status: .badRequest,
            message: "Invalid JSON: \(error.localizedDescription)",
            type: "invalid_request_error"
        )
    }

    // Validate: must have at least one message
    guard !chatRequest.messages.isEmpty else {
        return openAIError(
            status: .badRequest,
            message: "'messages' must contain at least one message",
            type: "invalid_request_error"
        )
    }

    // Validate: last message should be from user
    guard chatRequest.messages.last?.role == "user" else {
        return openAIError(
            status: .badRequest,
            message: "Last message must have role 'user'",
            type: "invalid_request_error"
        )
    }

    // Extract system prompt (first system message, if any)
    let systemPrompt = chatRequest.messages.first(where: { $0.role == "system" })?.content

    // Create session
    let session = makeSession(systemPrompt: systemPrompt)

    // Get user messages (excluding system)
    let userAssistantMessages = chatRequest.messages.filter { $0.role != "system" }

    // Replay history: feed all messages except the last one to build context
    if userAssistantMessages.count > 1 {
        for msg in userAssistantMessages.dropLast() {
            if msg.role == "user" {
                // Feed user message and discard response to build session context
                let _ = try await session.respond(to: msg.content)
            }
            // Assistant messages are implicitly part of session history after respond()
        }
    }

    // The final user message
    let finalPrompt = userAssistantMessages.last!.content
    let requestId = "chatcmpl-\(UUID().uuidString.prefix(12).lowercased())"
    let created = Int(Date().timeIntervalSince1970)

    // Streaming or non-streaming?
    if chatRequest.stream == true {
        return streamingResponse(session: session, prompt: finalPrompt, id: requestId, created: created)
    } else {
        return try await nonStreamingResponse(session: session, prompt: finalPrompt, id: requestId, created: created)
    }
}

// MARK: - Non-Streaming Response

private func nonStreamingResponse(
    session: LanguageModelSession,
    prompt: String,
    id: String,
    created: Int
) async throws -> Response {
    let result = try await session.respond(to: prompt)
    let content = result.content

    let promptTokens = estimateTokens(prompt)
    let completionTokens = estimateTokens(content)

    let response = ChatCompletionResponse(
        id: id,
        object: "chat.completion",
        created: created,
        model: modelName,
        choices: [.init(
            index: 0,
            message: OpenAIMessage(role: "assistant", content: content),
            finish_reason: "stop"
        )],
        usage: .init(
            prompt_tokens: promptTokens,
            completion_tokens: completionTokens,
            total_tokens: promptTokens + completionTokens
        )
    )

    let body = jsonString(response)
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: ByteBuffer(string: body))
    )
}

// MARK: - Streaming Response (SSE)

private func streamingResponse(
    session: LanguageModelSession,
    prompt: String,
    id: String,
    created: Int
) -> Response {
    var headers = HTTPFields()
    headers[.contentType] = "text/event-stream"
    headers[.cacheControl] = "no-cache"
    headers[.init("Connection")!] = "keep-alive"

    let responseStream = AsyncStream<ByteBuffer> { continuation in
        Task {
            // Send role announcement
            let roleChunk = sseRoleChunk(id: id, created: created)
            continuation.yield(ByteBuffer(string: sseDataLine(roleChunk)))

            // Stream model response
            let stream = session.streamResponse(to: prompt)
            var prev = ""

            do {
                for try await snapshot in stream {
                    let content = snapshot.content
                    if content.count > prev.count {
                        let idx = content.index(content.startIndex, offsetBy: prev.count)
                        let delta = String(content[idx...])
                        let chunk = sseContentChunk(id: id, created: created, content: delta)
                        continuation.yield(ByteBuffer(string: sseDataLine(chunk)))
                    }
                    prev = content
                }

                // Send stop chunk
                let stopChunk = sseStopChunk(id: id, created: created)
                continuation.yield(ByteBuffer(string: sseDataLine(stopChunk)))

                // Send [DONE]
                continuation.yield(ByteBuffer(string: sseDone))
            } catch {
                // On error, send an error event and close
                let errMsg = "data: {\"error\":\"\(error.localizedDescription)\"}\n\n"
                continuation.yield(ByteBuffer(string: errMsg))
            }

            continuation.finish()
        }
    }

    return Response(
        status: .ok,
        headers: headers,
        body: .init(asyncSequence: responseStream)
    )
}

// MARK: - Error Helpers

/// Create an OpenAI-formatted error response.
func openAIError(status: HTTPResponse.Status, message: String, type: String, code: String? = nil) -> Response {
    let error = OpenAIErrorResponse(
        error: .init(message: message, type: type, param: nil, code: code)
    )
    let body = jsonString(error)
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    return Response(
        status: status,
        headers: headers,
        body: .init(byteBuffer: ByteBuffer(string: body))
    )
}
