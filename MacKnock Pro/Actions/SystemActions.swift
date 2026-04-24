// SystemActions.swift
// MacKnock Pro
//
// System-level actions: lock screen, screenshot, DND, launch app, run shortcut.

import Foundation
import AppKit

/// System-level actions triggered by knock patterns
enum SystemActions {
    
    // MARK: - Lock Screen
    
    /// Lock the screen using the system menu command
    static func lockScreen() throws {
        // Method: Use the loginwindow CGSession key
        // This is equivalent to pressing Ctrl+Cmd+Q
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Create Ctrl+Cmd+Q key event
        // Q = keyCode 12
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false) else {
            // Fallback: use pmset
            try runCommand("/usr/bin/pmset", arguments: ["displaysleepnow"])
            return
        }
        
        keyDown.flags = [.maskCommand, .maskControl]
        keyUp.flags = [.maskCommand, .maskControl]
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    // MARK: - Screenshot
    
    /// Take a screenshot (saves to Desktop)
    static func takeScreenshot() throws {
        // Use the screencapture CLI tool
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let desktopPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Screenshot \(timestamp).png")
            .path
        
        try runCommand("/usr/sbin/screencapture", arguments: ["-x", desktopPath])
    }
    
    // MARK: - Do Not Disturb
    
    /// Toggle Do Not Disturb / Focus mode
    static func toggleDoNotDisturb() throws {
        // Use shortcuts to toggle Focus
        // Alternatively, simulate the keyboard shortcut
        _ = CGEventSource(stateID: .hidSystemState)
        
        // This opens the Notification Center, which can be used to toggle DND
        // The shortcut is clicking the date/time in the menu bar
        // Better approach: use the 'shortcuts' CLI if available
        let script = """
        tell application "System Events"
            tell process "ControlCenter"
                click menu bar item "Focus" of menu bar 1
            end tell
        end tell
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
    }
    
    // MARK: - Launch App
    
    /// Launch an application by path or bundle identifier
    static func launchApp(path: String) throws {
        let url: URL
        
        if path.hasSuffix(".app") {
            url = URL(fileURLWithPath: path)
        } else {
            // Try as bundle identifier
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: path) else {
                throw ActionError.appNotFound(path)
            }
            url = appURL
        }
        
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
    
    // MARK: - Run Shortcut
    
    /// Run an Apple Shortcut by name
    static func runShortcut(name: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ActionError.shortcutFailed("\(name): \(errorMsg)")
        }
    }
    
    // MARK: - Helper
    
    /// Run a shell command synchronously
    private static func runCommand(_ path: String, arguments: [String] = []) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ActionError.commandFailed(errorMsg)
        }
    }
}
