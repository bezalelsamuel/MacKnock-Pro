// CustomScriptAction.swift
// MacKnock Pro
//
// Execute custom shell scripts or AppleScript on knock detection.

import Foundation

/// Execute custom scripts triggered by knock patterns
enum CustomScriptAction {

    /// Execute a shell script string
    static func execute(script: String) async throws {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ActionError.invalidConfiguration("Custom Script requires script content.")
        }

        if trimmed.hasPrefix("tell ") || trimmed.contains("tell application") {
            try await executeAppleScript(trimmed)
        } else {
            try await executeShellScript(trimmed)
        }
    }

    /// Execute a shell script via /bin/zsh without blocking the concurrency thread pool.
    static func executeShellScript(_ script: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try await runProcessAsync(process, errorPipe: errorPipe, errorBuilder: ActionError.scriptFailed)
    }

    /// Execute an AppleScript via osascript without blocking the concurrency thread pool.
    static func executeAppleScript(_ script: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try await runProcessAsync(process, errorPipe: errorPipe, errorBuilder: ActionError.scriptFailed)
    }

    /// Runs a Process and suspends the caller (not a thread) until it exits.
    private static func runProcessAsync(
        _ process: Process,
        errorPipe: Pipe,
        errorBuilder: @escaping (String) -> ActionError
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    cont.resume(throwing: errorBuilder(msg))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
