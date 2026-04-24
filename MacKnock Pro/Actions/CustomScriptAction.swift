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
        
        // Detect script type
        if trimmed.hasPrefix("tell ") || trimmed.contains("tell application") {
            // AppleScript
            try await executeAppleScript(trimmed)
        } else {
            // Shell script
            try await executeShellScript(trimmed)
        }
    }
    
    /// Execute a shell script via /bin/zsh
    static func executeShellScript(_ script: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ActionError.scriptFailed(errorMsg)
        }
    }
    
    /// Execute an AppleScript via osascript
    static func executeAppleScript(_ script: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ActionError.scriptFailed(errorMsg)
        }
    }
}
