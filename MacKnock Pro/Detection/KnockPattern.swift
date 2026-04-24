// KnockPattern.swift
// MacKnock Pro
//
// Multi-knock pattern recognition: double, triple, quad knock.
// Buffers knock events within time windows to detect patterns.

import Foundation
import Combine

// MARK: - Knock Pattern Types

/// The pattern of knocks detected.
/// Single knock is no longer supported — patterns start at double.
enum KnockPatternType: String, CaseIterable, Codable, Identifiable {
    case double = "Double Knock"
    case triple = "Triple Knock"
    case quad   = "Quad Knock"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .double: return "hand.tap.fill"
        case .triple: return "burst.fill"
        case .quad:   return "4.circle.fill"
        }
    }

    var knockCount: Int {
        switch self {
        case .double: return 2
        case .triple: return 3
        case .quad:   return 4
        }
    }

    var description: String {
        switch self {
        case .double: return "Two quick knocks"
        case .triple: return "Three quick knocks"
        case .quad:   return "Four quick knocks"
        }
    }

    /// Timing window within which successive knocks must arrive (seconds).
    /// Quad gets a slightly wider window to allow for natural rhythm variation.
    var intraKnockWindow: TimeInterval {
        switch self {
        case .double: return 0.38
        case .triple: return 0.40
        case .quad:   return 0.44
        }
    }
}

/// A fully recognised knock-pattern event
struct KnockPatternEvent: Identifiable {
    let id = UUID()
    let pattern: KnockPatternType
    let time: Date
    let knockEvents: [KnockEvent]

    var averageAmplitude: Double {
        guard !knockEvents.isEmpty else { return 0 }
        return knockEvents.map(\.amplitude).reduce(0, +) / Double(knockEvents.count)
    }
}

// MARK: - Knock Pattern Recognizer

/// Recognises double, triple, and quad knock patterns by buffering
/// individual knock events within configurable timing windows.
///
/// State machine:
///   IDLE  → 1st knock arrives             → ACCUMULATING (start timeout)
///   ACCUM → knock within intraKnockWindow → add to buffer, restart timeout
///   ACCUM → timeout fires                 → flush buffer as pattern
///   ACCUM → 4th knock arrives             → flush immediately as quad
final class KnockPatternRecognizer: ObservableObject {

    // MARK: - Configuration

    /// Time gap allowed between consecutive knocks in a pattern (seconds).
    /// Per-pattern windows are baked into KnockPatternType.intraKnockWindow;
    /// this value acts as the global maximum inter-knock gap.
    var maxIntraKnockGap: TimeInterval = 0.44

    /// Extra grace period after the last knock before the buffer is flushed.
    /// Shorter = snappier response, longer = tolerates slower quad rhythms.
    var flushDelay: TimeInterval = 0.45

    /// Cooldown after a pattern fires — blocks new knocks for this duration
    /// to prevent accidental re-triggering. This is the user-facing "cooldown"
    /// setting (moved here from KnockDetector where it was blocking patterns).
    var patternCooldown: TimeInterval = 0.75

    // MARK: - Output

    let patternPublisher = PassthroughSubject<KnockPatternEvent, Never>()

    @Published var lastPattern: KnockPatternEvent?

    // MARK: - Private

    private var bufferCount: Int = 0
    private var knockBuffer: [KnockEvent?] = [nil, nil, nil, nil]
    private var lastKnockTime: Double = 0

    /// Wall-clock time when the last pattern was emitted (for cooldown)
    private var lastPatternEmitTime: Date = .distantPast

    // MARK: - Public API

    func handleKnock(_ event: KnockEvent) {
        // Respect pattern cooldown — ignore knocks that arrive too soon
        // after the last emitted pattern to prevent re-triggering.
        let now = Date()
        if now.timeIntervalSince(lastPatternEmitTime) < patternCooldown {
            return
        }

        let eventTime = event.machTimestamp

        if bufferCount > 0 {
            let gap = eventTime - lastKnockTime
            if gap > maxIntraKnockGap {
                flushBuffer()
            }
        }

        if bufferCount < 4 {
            knockBuffer[bufferCount] = event
            bufferCount += 1
        }

        lastKnockTime = eventTime

        if bufferCount >= 4 {
            flushBuffer()
        }
    }

    func tick(time: Double) {
        guard bufferCount > 0 else { return }
        if time - lastKnockTime > flushDelay {
            flushBuffer()
        }
    }

    // MARK: - State Machine

    private func flushBuffer() {
        guard bufferCount > 0 else { return }

        var events = [KnockEvent]()
        for i in 0..<bufferCount {
            if let ev = knockBuffer[i] { events.append(ev) }
            knockBuffer[i] = nil
        }
        let count = bufferCount
        bufferCount = 0

        guard count >= 2 else { return }

        let pattern: KnockPatternType
        switch count {
        case 2: pattern = .double
        case 3: pattern = .triple
        default: pattern = .quad
        }

        emit(pattern, events: events)
    }

    private func emit(_ type: KnockPatternType, events: [KnockEvent]) {
        lastPatternEmitTime = Date()
        let ev = KnockPatternEvent(pattern: type, time: Date(), knockEvents: events)
        DispatchQueue.main.async { [weak self] in self?.lastPattern = ev }
        patternPublisher.send(ev)
    }
}
