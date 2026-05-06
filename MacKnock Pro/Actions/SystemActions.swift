// SystemActions.swift
// MacKnock Pro
//
// System-level actions: lock screen, screenshot, DND, launch app, run shortcut.

import Foundation
import AppKit

/// System-level actions triggered by knock patterns
enum SystemActions {

    // MARK: - Lock Screen

    /// Lock the screen (Ctrl+Cmd+Q), falling back to pmset displaysleepnow.
    static func lockScreen() throws {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false) else {
            try runCommandSync("/usr/bin/pmset", arguments: ["displaysleepnow"])
            return
        }

        keyDown.flags = [.maskCommand, .maskControl]
        keyUp.flags   = [.maskCommand, .maskControl]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Screenshot

    /// Take a screenshot to the real user's Desktop.
    /// When running as root via sudo, SUDO_USER holds the original user's name.
    static func takeScreenshot() throws {
        let userHome: URL
        if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"], !sudoUser.isEmpty {
            userHome = URL(fileURLWithPath: "/Users/\(sudoUser)")
        } else {
            userHome = FileManager.default.homeDirectoryForCurrentUser
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = dateFormatter.string(from: Date())

        let desktopPath = userHome
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Screenshot \(timestamp).png")
            .path

        try runCommandSync("/usr/sbin/screencapture", arguments: ["-x", desktopPath])
    }

    // MARK: - Do Not Disturb

    /// Toggle Do Not Disturb / Focus mode via AppleScript.
    static func toggleDoNotDisturb() throws {
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
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Launch App

    /// Launch an application by path or bundle identifier.
    static func launchApp(path: String) throws {
        let url: URL
        if path.hasSuffix(".app") {
            url = URL(fileURLWithPath: path)
        } else {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: path) else {
                throw ActionError.appNotFound(path)
            }
            url = appURL
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Run Shortcut

    /// Run an Apple Shortcut by name without blocking the concurrency thread pool.
    static func runShortcut(name: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg  = String(data: data, encoding: .utf8) ?? "Unknown error"
                    cont.resume(throwing: ActionError.shortcutFailed("\(name): \(msg)"))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Synchronous helper (used for lock-screen fallback and screencapture)

    private static func runCommandSync(_ path: String, arguments: [String] = []) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let msg  = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ActionError.commandFailed(msg)
        }
    }
}
