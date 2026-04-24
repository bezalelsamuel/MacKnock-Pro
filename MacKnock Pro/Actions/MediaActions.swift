// MediaActions.swift
// MacKnock Pro
//
// Media control actions using simulated media key events.
// Uses CGEvent to simulate the hardware media keys (F7/F8/F9 equivalents).

import Foundation
import AppKit
import Carbon.HIToolbox

/// Media control actions via simulated system key events
enum MediaActions {
    
    // Media key codes (NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h)
    private static let NX_KEYTYPE_PLAY: UInt32 = 16
    private static let NX_KEYTYPE_NEXT: UInt32 = 17
    private static let NX_KEYTYPE_PREVIOUS: UInt32 = 18
    private static let NX_KEYTYPE_SOUND_UP: UInt32 = 0
    private static let NX_KEYTYPE_SOUND_DOWN: UInt32 = 1
    private static let NX_KEYTYPE_MUTE: UInt32 = 7
    
    // MARK: - Media Controls
    
    /// Toggle play/pause for the current media player
    static func togglePlayPause() throws {
        try sendMediaKey(NX_KEYTYPE_PLAY)
    }
    
    /// Skip to the next track
    static func nextTrack() throws {
        try sendMediaKey(NX_KEYTYPE_NEXT)
    }
    
    /// Go to the previous track
    static func previousTrack() throws {
        try sendMediaKey(NX_KEYTYPE_PREVIOUS)
    }
    
    /// Increase system volume
    static func volumeUp() throws {
        try sendMediaKey(NX_KEYTYPE_SOUND_UP)
    }
    
    /// Decrease system volume
    static func volumeDown() throws {
        try sendMediaKey(NX_KEYTYPE_SOUND_DOWN)
    }
    
    /// Toggle system mute
    static func toggleMute() throws {
        try sendMediaKey(NX_KEYTYPE_MUTE)
    }
    
    // MARK: - Key Event Simulation
    
    /// Send a media key event (key down + key up) using CGEvent.
    /// This simulates pressing the hardware media keys (play/pause, etc.)
    private static func sendMediaKey(_ keyType: UInt32) throws {
        // Create key down event
        // The media key data is packed into: (keyType << 16) | (flags << 8)
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTON
            data1: Int((keyType << 16) | (0xa << 8)),  // key down flag
            data2: -1
        )
        
        // Create key up event
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((keyType << 16) | (0xb << 8)),  // key up flag
            data2: -1
        )
        
        guard let downEvent = keyDown?.cgEvent, let upEvent = keyUp?.cgEvent else {
            throw ActionError.eventCreationFailed
        }
        
        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
    }
}

// MARK: - Errors

enum ActionError: LocalizedError {
    case eventCreationFailed
    case commandFailed(String)
    case appNotFound(String)
    case shortcutFailed(String)
    case scriptFailed(String)
    case permissionDenied
    case invalidConfiguration(String)
    
    var errorDescription: String? {
        switch self {
        case .eventCreationFailed:
            return "Failed to create system event"
        case .commandFailed(let msg):
            return "Command failed: \(msg)"
        case .appNotFound(let path):
            return "Application not found: \(path)"
        case .shortcutFailed(let name):
            return "Shortcut failed: \(name)"
        case .scriptFailed(let msg):
            return "Script failed: \(msg)"
        case .permissionDenied:
            return "Permission denied"
        case .invalidConfiguration(let msg):
            return msg
        }
    }
}
