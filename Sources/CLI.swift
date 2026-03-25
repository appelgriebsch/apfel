// ============================================================================
// CLI.swift — Command-line interface commands
// Part of apfel — Apple Intelligence from the command line
// ============================================================================

import FoundationModels
import Foundation

// MARK: - Chat Header

/// Print the chat mode header (app name, version, separator line).
/// Suppressed in --quiet mode. Routed to stderr in JSON mode.
func printHeader() {
    guard !quietMode else { return }
    let header = styled("Apple Intelligence", .cyan, .bold)
        + styled(" · on-device LLM · \(appName) v\(version)", .dim)
    let line = styled(String(repeating: "─", count: 56), .dim)
    if outputFormat == .json {
        printStderr(header)
        printStderr(line)
    } else {
        print(header)
        print(line)
    }
}

// MARK: - Single Prompt

/// Handle a single (non-interactive) prompt.
///
/// Behavior depends on output format:
/// - **plain**: Print response directly. If streaming, print tokens as they arrive.
/// - **json**: Buffer the complete response, then emit a single JSON object.
func singlePrompt(_ prompt: String, systemPrompt: String?, stream: Bool) async throws {
    let session = makeSession(systemPrompt: systemPrompt)

    switch outputFormat {
    case .plain:
        if stream {
            let _ = try await collectStream(session, prompt: prompt, printDelta: true)
            print()
        } else {
            let response = try await session.respond(to: prompt)
            print(response.content)
        }

    case .json:
        let content: String
        if stream {
            content = try await collectStream(session, prompt: prompt, printDelta: false)
        } else {
            let response = try await session.respond(to: prompt)
            content = response.content
        }
        let obj = ApfelResponse(
            model: modelName,
            content: content,
            metadata: .init(onDevice: true, version: version)
        )
        print(jsonString(obj))
    }
}

// MARK: - Interactive Chat

/// Run an interactive multi-turn chat session.
func chat(systemPrompt: String?) async throws {
    guard isatty(STDIN_FILENO) != 0 else {
        printError("--chat requires an interactive terminal (stdin must be a TTY)")
        exit(exitUsageError)
    }

    let session = makeSession(systemPrompt: systemPrompt)
    var turn = 0

    printHeader()
    if !quietMode {
        if let sys = systemPrompt {
            let sysLine = styled("system: ", .magenta, .bold) + styled(sys, .dim)
            if outputFormat == .json {
                printStderr(sysLine)
            } else {
                print(sysLine)
            }
        }
        let hint = styled("Type 'quit' to exit.\n", .dim)
        if outputFormat == .json {
            printStderr(hint)
        } else {
            print(hint)
        }
    }

    while true {
        if !quietMode {
            let prompt = styled("you› ", .green, .bold)
            if outputFormat == .json {
                stderr.write(Data(prompt.utf8))
            } else {
                print(prompt, terminator: "")
            }
        }
        fflush(stdout)

        guard let input = readLine() else { break }
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        if trimmed.lowercased() == "quit" || trimmed.lowercased() == "exit" { break }

        turn += 1

        if outputFormat == .json {
            print(jsonString(
                ChatMessage(role: "user", content: trimmed, model: nil),
                pretty: false
            ))
            fflush(stdout)
        }

        if !quietMode && outputFormat == .plain {
            print(styled(" ai› ", .cyan, .bold), terminator: "")
            fflush(stdout)
        }

        switch outputFormat {
        case .plain:
            let _ = try await collectStream(session, prompt: trimmed, printDelta: true)
            print("\n")

        case .json:
            let content = try await collectStream(session, prompt: trimmed, printDelta: false)
            print(jsonString(
                ChatMessage(role: "assistant", content: content, model: modelName),
                pretty: false
            ))
            fflush(stdout)
        }
    }

    if !quietMode {
        let bye = styled("\nGoodbye.", .dim)
        if outputFormat == .json {
            printStderr(bye)
        } else {
            print(bye)
        }
    }
}

// MARK: - Usage

/// Print the help text. Styled with ANSI colors when on a TTY.
func printUsage() {
    print("""
    \(styled(appName, .cyan, .bold)) v\(version) — Apple Intelligence from the command line

    \(styled("USAGE:", .yellow, .bold))
      \(appName) [OPTIONS] <prompt>       Send a single prompt
      \(appName) --chat                   Interactive conversation
      \(appName) --stream <prompt>        Stream a single response
      \(appName) --serve                  Start OpenAI-compatible HTTP server

    \(styled("OPTIONS:", .yellow, .bold))
      -s, --system <text>     Set a system prompt to guide the model
      -o, --output <format>   Output format: plain, json [default: plain]
      -q, --quiet             Suppress non-essential output
          --no-color           Disable colored output
      -h, --help              Show this help
      -v, --version           Print version

    \(styled("SERVER OPTIONS:", .yellow, .bold))
          --serve              Start OpenAI-compatible HTTP server
          --port <number>      Server port [default: 11434]
          --host <address>     Bind address [default: 127.0.0.1]
          --cors               Enable CORS headers for browser clients
          --max-concurrent <n> Max concurrent model requests [default: 5]
          --debug              Verbose logging with full request/response bodies

    \(styled("ENVIRONMENT:", .yellow, .bold))
      NO_COLOR                Disable colored output (https://no-color.org)

    \(styled("EXAMPLES:", .yellow, .bold))
      \(appName) "What is the capital of Austria?"
      \(appName) --stream "Write a haiku about code"
      \(appName) -s "You are a pirate" --chat
      echo "Summarize this" | \(appName)
      \(appName) -o json "Translate to German: hello" | jq .content
      \(appName) --serve
      \(appName) --serve --port 3000 --host 0.0.0.0 --cors
    """)
}
