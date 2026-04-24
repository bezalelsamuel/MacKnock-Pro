// MacKnockProApp.swift
// MacKnock Pro
//
// App entry point with MenuBarExtra and Settings window.

import SwiftUI
import AppKit

@main
struct MacKnockProApp: App {
    
    @StateObject private var appState = AppState()
    @StateObject private var settings = SettingsManager.shared
    
    var body: some Scene {
        // Menu Bar
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(settings)
        } label: {
            Label("MacKnock Pro", systemImage: settings.menuBarIconStyle.systemImage)
        }
        .menuBarExtraStyle(.window)
        
        // Settings Window
        Window("MacKnock Pro Settings", id: "settings") {
            MainSettingsView()
                .environmentObject(appState)
                .environmentObject(settings)
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 620)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - App State

/// Central app state that wires sensor → detector → pattern → actions
@MainActor
final class AppState: ObservableObject {
    
    @Published var isListening = false
    @Published var sensorAvailable = false
    @Published var lastKnockTime: Date?
    @Published var lastKnockAmplitude: Double = 0
    @Published var totalKnocks: Int = 0
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?
    
    let accelerometer = AccelerometerService.shared
    let detector = KnockDetector()
    let patternRecognizer = KnockPatternRecognizer()
    let actionExecutor = ActionExecutor()
    
    private var cancellables = Set<AnyCancellable>()
    private var wasListeningBeforeSleep = false
    private var lastAppliedEnabledState: Bool?
    
    init() {
        sensorAvailable = accelerometer.checkAvailability()
        setupBindings()
        setupLifecycle()
        actionExecutor.loadConfiguration()
        applyRuntimeSettings()
        applyEnabledSettingIfNeeded(force: true)
    }
    
    private func setupBindings() {
        // Wire: pattern recognizer → action executor
        actionExecutor.subscribe(to: patternRecognizer)
        
        // Wire: detector → pattern recognizer & UI
        detector.onKnock = { [weak self] event in
            // Route to pattern recognizer on the same thread
            self?.patternRecognizer.handleKnock(event)
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self?.lastKnockTime = event.time
                self?.lastKnockAmplitude = event.amplitude
                self?.totalKnocks += 1
            }
        }
        
        // Track accelerometer errors
        accelerometer.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error
                self?.statusMessage = "Error: \(error)"
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyRuntimeSettings()
                self.applyEnabledSettingIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func setupLifecycle() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wasListeningBeforeSleep = self.isListening
                if self.isListening {
                    self.stopListening()
                    self.statusMessage = "Sleeping"
                }
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.wasListeningBeforeSleep else { return }
                // Give the SPU sensor a moment to reinitialize after wake
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.startListening()
            }
        }
    }

    private func applyRuntimeSettings() {
        let settings = SettingsManager.shared
        detector.amplitudeFloor = settings.minAmplitude
        patternRecognizer.patternCooldown = settings.cooldownSeconds
        actionExecutor.soundFeedback = settings.soundFeedback
    }

    private func applyEnabledSettingIfNeeded(force: Bool = false) {
        let enabled = SettingsManager.shared.isEnabled
        guard force || enabled != lastAppliedEnabledState else { return }
        lastAppliedEnabledState = enabled

        if enabled {
            startListening()
        } else {
            if isListening {
                stopListening()
            }
            statusMessage = "Disabled"
        }
    }

    // MARK: - Adaptive engine shortcut (for UI binding)
    var adaptiveEngine: AdaptiveThresholdEngine { detector.adaptiveThreshold }
    var hasRootPrivileges: Bool { geteuid() == 0 }
    var launchCommand: String {
        if let executablePath = Bundle.main.executablePath {
            return "sudo \"\(executablePath)\""
        }
        return "sudo /path/to/MacKnock Pro.app/Contents/MacOS/MacKnock Pro"
    }
    
    // MARK: - Controls
    
    func startListening() {
        guard !isListening else { return }
        guard SettingsManager.shared.isEnabled else {
            statusMessage = "Disabled"
            return
        }

        applyRuntimeSettings()

        // Confirm-knock feedback: when an action fires, it means the knock was real.
        // Notify the adaptive engine so it can strengthen the knock-class model.
        actionExecutor.onKnockConfirmed = { [weak self] amplitude in
            self?.detector.adaptiveThreshold.confirmKnock(amplitude: amplitude)
        }

        // Start sensor
        accelerometer.start()
        guard accelerometer.isRunning else {
            isListening = false
            let rootError = "Root privileges required for accelerometer access. Run with sudo."
            let message = accelerometer.errorMessage ?? "Sensor unavailable"
            errorMessage = message
            statusMessage = (message == rootError) ? "Needs sudo (root)" : message
            return
        }

        // Connect detector to sensor inline
        accelerometer.setCallback { [weak detector, weak patternRecognizer] ax, ay, az, time in
            detector?.process(ax: ax, ay: ay, az: az, time: time)
            patternRecognizer?.tick(time: time)
        }
        detector.start()

        isListening = true
        statusMessage = "Listening for knocks…"
    }
    
    func stopListening() {
        accelerometer.setCallback { _, _, _, _ in }
        detector.stop()
        accelerometer.stop()
        isListening = false
        statusMessage = "Paused"
    }
    
    func toggleListening() {
        setEnabled(!SettingsManager.shared.isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        SettingsManager.shared.isEnabled = enabled
        applyEnabledSettingIfNeeded(force: true)
    }
}

// Need Combine for the publisher subscriptions
import Combine
