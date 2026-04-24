// ActionExecutor.swift
// MacKnock Pro
//
// Protocol-based action system and executor that maps knock patterns to actions.

import Foundation
import Combine
import AppKit

// MARK: - Action Protocol

/// Represents an action that can be triggered by a knock pattern.
enum KnockActionType: String, CaseIterable, Codable, Identifiable {
    case none = "None"
    case playPause = "Play/Pause"
    case nextTrack = "Next Track"
    case previousTrack = "Previous Track"
    case volumeUp = "Volume Up"
    case volumeDown = "Volume Down"
    case mute = "Mute/Unmute"
    case lockScreen = "Lock Screen"
    case screenshot = "Screenshot"
    case toggleDND = "Do Not Disturb"
    case launchApp = "Launch App"
    case runShortcut = "Run Shortcut"
    case customScript = "Custom Script"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .none:          return "nosign"
        case .playPause:     return "playpause.fill"
        case .nextTrack:     return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .volumeUp:      return "speaker.wave.3.fill"
        case .volumeDown:    return "speaker.wave.1.fill"
        case .mute:          return "speaker.slash.fill"
        case .lockScreen:    return "lock.fill"
        case .screenshot:    return "camera.fill"
        case .toggleDND:     return "moon.fill"
        case .launchApp:     return "app.fill"
        case .runShortcut:   return "bolt.fill"
        case .customScript:  return "terminal.fill"
        }
    }
    
    var category: ActionCategory {
        switch self {
        case .none: return .none
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute:
            return .media
        case .lockScreen, .screenshot, .toggleDND:
            return .system
        case .launchApp, .runShortcut, .customScript:
            return .custom
        }
    }
    
    var requiresParameter: Bool {
        switch self {
        case .launchApp, .runShortcut, .customScript: return true
        default: return false
        }
    }
}

enum ActionCategory: String, CaseIterable {
    case none = "None"
    case media = "Media"
    case system = "System"
    case custom = "Custom"
}

// MARK: - Action Configuration

/// A configured action with its parameters
struct ActionConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var actionType: KnockActionType
    var parameter: String  // App path, shortcut name, or script content
    
    init(actionType: KnockActionType = .none, parameter: String = "") {
        self.id = UUID()
        self.actionType = actionType
        self.parameter = parameter
    }
    
    static func == (lhs: ActionConfiguration, rhs: ActionConfiguration) -> Bool {
        lhs.actionType == rhs.actionType && lhs.parameter == rhs.parameter
    }
}

// MARK: - Action Executor

/// Executes actions in response to knock pattern events.
@MainActor
final class ActionExecutor: ObservableObject {
    
    /// Maps knock patterns to their configured actions
    @Published var patternActions: [KnockPatternType: ActionConfiguration] = [
        .double: ActionConfiguration(actionType: .playPause),
        .triple: ActionConfiguration(actionType: .nextTrack),
        .quad:   ActionConfiguration(actionType: .lockScreen),
    ]
    
    /// Whether to play haptic/sound feedback on knock detection
    @Published var soundFeedback = true
    
    /// Log of recent action executions
    @Published var recentActions: [ActionLogEntry] = []
    
    private var cancellables = Set<AnyCancellable>()

    /// Called after a knock pattern successfully fires an action.
    /// Use this to feed the confirmed amplitude back to the adaptive engine.
    var onKnockConfirmed: ((Double) -> Void)?
    
    // MARK: - Subscribe to Pattern Recognizer
    
    func subscribe(to recognizer: KnockPatternRecognizer) {
        recognizer.patternPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] patternEvent in
                self?.handlePattern(patternEvent)
            }
            .store(in: &cancellables)
    }
    
    func unsubscribe() {
        cancellables.removeAll()
    }
    
    // MARK: - Action Execution
    
    func handlePattern(_ pattern: KnockPatternEvent) {
        guard let config = patternActions[pattern.pattern],
              config.actionType != .none else { return }
        
        // Play feedback sound
        if soundFeedback {
            playFeedbackSound()
        }
        
        // Execute the action
        Task {
            do {
                try await execute(config)
                logAction(pattern: pattern.pattern, action: config, success: true)
                // Feedback loop: action fired = knock was definitely real
                onKnockConfirmed?(pattern.averageAmplitude)
            } catch {
                logAction(pattern: pattern.pattern, action: config, success: false, error: error.localizedDescription)
            }
        }
    }
    
    func execute(_ config: ActionConfiguration) async throws {
        if let message = validationMessage(for: config) {
            throw ActionError.invalidConfiguration(message)
        }

        let parameter = normalizedParameter(config.parameter)

        switch config.actionType {
        case .none:
            break
        case .playPause:
            try MediaActions.togglePlayPause()
        case .nextTrack:
            try MediaActions.nextTrack()
        case .previousTrack:
            try MediaActions.previousTrack()
        case .volumeUp:
            try MediaActions.volumeUp()
        case .volumeDown:
            try MediaActions.volumeDown()
        case .mute:
            try MediaActions.toggleMute()
        case .lockScreen:
            try SystemActions.lockScreen()
        case .screenshot:
            try SystemActions.takeScreenshot()
        case .toggleDND:
            try SystemActions.toggleDoNotDisturb()
        case .launchApp:
            try SystemActions.launchApp(path: parameter)
        case .runShortcut:
            try await SystemActions.runShortcut(name: parameter)
        case .customScript:
            try await CustomScriptAction.execute(script: parameter)
        }
    }

    func validationMessage(for config: ActionConfiguration) -> String? {
        let parameter = normalizedParameter(config.parameter)

        switch config.actionType {
        case .none,
             .playPause,
             .nextTrack,
             .previousTrack,
             .volumeUp,
             .volumeDown,
             .mute,
             .lockScreen,
             .screenshot,
             .toggleDND:
            return nil

        case .launchApp:
            guard !parameter.isEmpty else {
                return "Launch App requires an app path or bundle identifier."
            }

            if parameter.hasSuffix(".app") {
                let expanded = (parameter as NSString).expandingTildeInPath
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
                if !exists || !isDirectory.boolValue {
                    return "App path not found: \(parameter)"
                }
            }
            return nil

        case .runShortcut:
            return parameter.isEmpty ? "Run Shortcut requires a Shortcut name." : nil

        case .customScript:
            return parameter.isEmpty ? "Custom Script requires script content." : nil
        }
    }

    private func normalizedParameter(_ parameter: String) -> String {
        parameter.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Feedback
    
    private func playFeedbackSound() {
        NSSound(named: "Tink")?.play()
    }
    
    // MARK: - Logging
    
    private func logAction(pattern: KnockPatternType, action: ActionConfiguration, success: Bool, error: String? = nil) {
        let entry = ActionLogEntry(
            time: Date(),
            pattern: pattern,
            action: action.actionType,
            success: success,
            error: error
        )
        recentActions.insert(entry, at: 0)
        if recentActions.count > 50 {
            recentActions = Array(recentActions.prefix(50))
        }
    }
    
    // MARK: - Persistence
    
    func saveConfiguration() {
        if let data = try? JSONEncoder().encode(patternActions) {
            UserDefaults.standard.set(data, forKey: "patternActions")
        }
    }
    
    func loadConfiguration() {
        if let data = UserDefaults.standard.data(forKey: "patternActions"),
           let actions = try? JSONDecoder().decode([KnockPatternType: ActionConfiguration].self, from: data) {
            patternActions = actions
        }
    }
}

// MARK: - Action Log Entry

struct ActionLogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let pattern: KnockPatternType
    let action: KnockActionType
    let success: Bool
    let error: String?
}
