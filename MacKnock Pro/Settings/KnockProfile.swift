// KnockProfile.swift
// MacKnock Pro
//
// Predefined sensitivity profiles for different use cases.

import Foundation

/// A predefined sensitivity profile
struct KnockProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let minAmplitude: Double
    let cooldownMs: Int
    
    // MARK: - Predefined Profiles
    
    /// Very sensitive — detects light taps
    static let sensitive = KnockProfile(
        id: "sensitive",
        name: "Sensitive",
        description: "Detects light taps and gentle touches",
        icon: "hare.fill",
        minAmplitude: 0.03,
        cooldownMs: 600
    )
    
    /// Balanced — firm knocks only (default)
    static let balanced = KnockProfile(
        id: "balanced",
        name: "Balanced",
        description: "Responds to firm knocks while ignoring vibrations",
        icon: "hand.tap.fill",
        minAmplitude: 0.08,
        cooldownMs: 750
    )
    
    /// Strong — only hard impacts
    static let strong = KnockProfile(
        id: "strong",
        name: "Strong",
        description: "Only responds to hard, deliberate knocks",
        icon: "tortoise.fill",
        minAmplitude: 0.20,
        cooldownMs: 1000
    )
    
    /// Fast — optimized for rapid interaction
    static let fast = KnockProfile(
        id: "fast",
        name: "Fast",
        description: "Quick response with shorter cooldown for rapid knocking",
        icon: "bolt.fill",
        minAmplitude: 0.10,
        cooldownMs: 350
    )
    
    /// All available profiles
    static let allProfiles: [KnockProfile] = [
        .sensitive, .balanced, .strong, .fast
    ]
    
    /// Find a profile by ID
    static func profile(for id: String) -> KnockProfile? {
        allProfiles.first { $0.id == id }
    }
}
