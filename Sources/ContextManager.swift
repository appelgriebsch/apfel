// ============================================================================
// ContextManager.swift — Convert OpenAI messages to LanguageModelSession
// Part of apfel — Apple Intelligence from the command line
//
// Uses FoundationModels Transcript API (macOS 26.1+) to reconstruct session
// state from OpenAI's stateless message history — NO re-inference on history.
// This is the core fix for the broken history-replay bug in the old Handlers.swift.
// ============================================================================

import FoundationModels
import Foundation
import ApfelCore

enum ContextManager {

    // MARK: - Session Factory

    /// Build a LanguageModelSession from OpenAI messages + optional tools.
    /// Returns the session (with history baked in) + the final user prompt.
    ///
    /// Architecture:
    /// - system message → Transcript.Instructions
    /// - user messages in history → Transcript.Prompt
    /// - assistant messages in history → Transcript.Response
    /// - tool result messages → Transcript.ToolOutput
    /// - tools list → injected into Instructions via ToolCallHandler
    /// - last user message → returned as finalPrompt (caller sends it via respond())
    static func makeSession(
        messages: [OpenAIMessage],
        tools: [OpenAITool]?,
        options: SessionOptions
    ) -> (session: LanguageModelSession, finalPrompt: String) {
        let conversation = messages.filter { $0.role != "system" }
        let finalPrompt = conversation.last?.textContent ?? ""
        let history = Array(conversation.dropLast())

        let model = makeModel(permissive: options.permissive)
        var entries: [Transcript.Entry] = []

        // Build instructions (system prompt + tool injection)
        let instrText = buildInstructions(messages: messages, tools: tools)
        if !instrText.isEmpty {
            let seg = Transcript.TextSegment(content: instrText)
            let instr = Transcript.Instructions(segments: [.text(seg)], toolDefinitions: [])
            entries.append(.instructions(instr))
        }

        // Build history entries
        for msg in history {
            switch msg.role {
            case "user":
                if let text = msg.textContent {
                    let seg = Transcript.TextSegment(content: text)
                    let genOpts = makeGenerationOptions(options)
                    let prompt = Transcript.Prompt(segments: [.text(seg)], options: genOpts)
                    entries.append(.prompt(prompt))
                }
            case "assistant":
                let text: String
                if let calls = msg.tool_calls, !calls.isEmpty,
                   let json = try? JSONEncoder().encode(calls),
                   let str = String(data: json, encoding: .utf8) {
                    text = str
                } else {
                    text = msg.textContent ?? ""
                }
                let seg = Transcript.TextSegment(content: text)
                let resp = Transcript.Response(assetIDs: [], segments: [.text(seg)])
                entries.append(.response(resp))
            case "tool":
                let text = msg.textContent ?? ""
                let seg = Transcript.TextSegment(content: text)
                let output = Transcript.ToolOutput(
                    id: msg.tool_call_id ?? UUID().uuidString,
                    toolName: msg.name ?? "tool",
                    segments: [.text(seg)]
                )
                entries.append(.toolOutput(output))
            default:
                break
            }
        }

        let session: LanguageModelSession
        if entries.isEmpty {
            session = LanguageModelSession(model: model)
        } else {
            let transcript = Transcript(entries: entries)
            session = LanguageModelSession(model: model, transcript: transcript)
        }
        return (session, finalPrompt)
    }

    // MARK: - Instructions Builder

    private static func buildInstructions(messages: [OpenAIMessage], tools: [OpenAITool]?) -> String {
        var parts: [String] = []

        if let sys = messages.first(where: { $0.role == "system" })?.textContent {
            parts.append(sys)
        }

        if let tools = tools, !tools.isEmpty {
            let defs = tools.map {
                ToolDef(
                    name: $0.function.name,
                    description: $0.function.description,
                    parametersJSON: $0.function.parameters?.value
                )
            }
            parts.append(ToolCallHandler.buildSystemPrompt(tools: defs))
        }

        return parts.joined(separator: "\n\n")
    }
}
