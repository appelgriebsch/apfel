// ============================================================================
// Server.swift — OpenAI-compatible HTTP server
// Part of apfel — Apple Intelligence from the command line
// ============================================================================

import Foundation
import Hummingbird

/// Server configuration passed from CLI argument parsing.
struct ServerConfig: Sendable {
    let host: String
    let port: Int
    let cors: Bool
    let maxConcurrent: Int
    let debug: Bool
}

/// Start the OpenAI-compatible HTTP server.
func startServer(config: ServerConfig) async throws {
    let router = Router()

    router.get("/health") { _, _ -> Response in
        jsonResponse("{\"status\":\"ok\",\"model\":\"\(modelName)\",\"version\":\"\(version)\"}")
    }
    router.get("/v1/models") { _, _ -> Response in
        jsonResponse(jsonString(ModelsListResponse(
            object: "list",
            data: [.init(id: modelName, object: "model", created: 1719792000, owned_by: "apple")]
        )))
    }
    router.post("/v1/chat/completions") { request, context -> Response in
        try await handleChatCompletion(request, context: context)
    }

    let app = Application(
        router: router,
        configuration: .init(
            address: .hostname(config.host, port: config.port)
        )
    )

    printStderr("""
    \(styled("apfel server", .cyan, .bold)) v\(version)
    \(styled("├", .dim)) endpoint: http://\(config.host):\(config.port)
    \(styled("├", .dim)) model:    \(modelName)
    \(styled("├", .dim)) cors:     \(config.cors ? "enabled" : "disabled")
    \(styled("├", .dim)) max concurrent: \(config.maxConcurrent)
    \(styled("├", .dim)) debug:    \(config.debug ? "on" : "off")
    \(styled("└", .dim)) ready
    """)

    printStderr("")
    printStderr(styled("Endpoints:", .yellow, .bold))
    printStderr("  POST http://\(config.host):\(config.port)/v1/chat/completions")
    printStderr("  GET  http://\(config.host):\(config.port)/v1/models")
    printStderr("  GET  http://\(config.host):\(config.port)/health")
    printStderr("")

    try await app.run()
}

// MARK: - Helpers

/// Create a JSON Response with proper Content-Type header.
func jsonResponse(_ body: String, status: HTTPResponse.Status = .ok) -> Response {
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    return Response(
        status: status,
        headers: headers,
        body: .init(byteBuffer: .init(string: body))
    )
}
