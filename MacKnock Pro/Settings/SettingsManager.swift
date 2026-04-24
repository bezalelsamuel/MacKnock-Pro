// SettingsManager.swift
// MacKnock Pro
//
// Centralized settings management with UserDefaults persistence.

import Foundation
import SwiftUI
import ServiceManagement

/// Centralized settings manager for MacKnock Pro
@MainActor
final class SettingsManager: ObservableObject {
    
    static let shared = SettingsManager()
    
    // MARK: - General Settings
    
    /// Whether knock detection is enabled
    @AppStorage("isEnabled") var isEnabled = true
    
    /// Whether to launch at login
    @AppStorage("launchAtLogin") var launchAtLogin = false {
        didSet {
            updateLaunchAtLogin()
        }
    }
    
    /// Whether to play sound feedback on knock detection
    @AppStorage("soundFeedback") var soundFeedback = true
    
    /// Whether to show notification on knock
    @AppStorage("showNotification") var showNotification = false
    
    // MARK: - Sensitivity Settings

    /// Amplitude floor — adaptive engine will never trigger below this value (0.005 - 0.30).
    /// Think of this as a noise guard, not the actual detection threshold.
    @AppStorage("minAmplitude") var minAmplitude: Double = 0.01

    /// Cooldown between knock responses in milliseconds
    @AppStorage("cooldownMs") var cooldownMs: Int = 750

    /// Active sensitivity profile
    @AppStorage("activeProfile") var activeProfile: String = KnockProfile.balanced.id
    
    // MARK: - Appearance
    
    /// Menu bar icon style
    @AppStorage("menuBarIconStyle") var menuBarIconStyle: MenuBarIconStyle = .waveform
    
    // MARK: - Computed
    
    var cooldownSeconds: TimeInterval {
        TimeInterval(cooldownMs) / 1000.0
    }
    
    // MARK: - Launch at Login
    
    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
    
    // MARK: - Apply Profile
    
    func applyProfile(_ profile: KnockProfile) {
        minAmplitude = profile.minAmplitude
        cooldownMs = profile.cooldownMs
        activeProfile = profile.id
    }
    
    // MARK: - Reset
    
    func resetToDefaults() {
        isEnabled = true
        soundFeedback = true
        showNotification = false
        minAmplitude = 0.01
        cooldownMs = 750
        menuBarIconStyle = .waveform
        applyProfile(.balanced)
    }
}

// MARK: - Menu Bar Icon Style

enum MenuBarIconStyle: String, CaseIterable, Codable {
    case waveform = "Waveform"
    case hand = "Hand"
    case dot = "Dot"
    
    var systemImage: String {
        switch self {
        case .waveform: return "waveform.path.ecg"
        case .hand:     return "hand.tap.fill"
        case .dot:      return "circle.fill"
        }
    }
}
