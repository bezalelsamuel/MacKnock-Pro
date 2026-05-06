// AdaptiveThresholdEngine.swift
// MacKnock Pro
//
// Online adaptive knock threshold using a 2-class Gaussian Mixture Model (GMM)
// with Fisher Linear Discriminant for optimal separating threshold.
//
// The engine maintains two running Gaussian models:
//   • Noise class  — models ambient vibration floor (low-amplitude, continuous)
//   • Knock class  — models intentional knock force (high-amplitude, impulsive)
//
// On every sample it:
//   1. Soft-assigns the sample to each class (E-step)
//   2. Updates class mean + variance via exponential forgetting (M-step)
//   3. Recomputes the Fisher optimal threshold between the two Gaussians
//
// Fisher 1-D threshold between two Gaussians:
//   t = (σ²_k · μ_n + σ²_n · μ_k) / (σ²_n + σ²_k)
// (variance-weighted midpoint — if knock has small spread it wins more room)
//
// Because knocks vary between users and sessions, we also track:
//   • A "session bias" that shifts the threshold toward recently observed
//     confirmed knock amplitudes, preventing drift from true negatives.
//   • A confidence score: how well-separated the two classes are
//     (Bhattacharyya distance). UI shows this as "Learning…" vs. "Calibrated".

import Foundation
import Combine
import os

// MARK: - Engine State (persisted across sessions)

struct AdaptiveThresholdState: Codable {
    // Noise Gaussian
    var noiseMean: Double  = 0.005
    var noiseVar:  Double  = 1e-6

    // Knock Gaussian
    var knockMean: Double  = 0.12
    var knockVar:  Double  = 0.003

    // Prior probability that any incoming event is a knock (estimated)
    var knockPrior: Double = 0.15

    // Number of samples processed (determines learning-rate decay)
    var samplesSeen: Int   = 0

    // Number of confirmed knocks (gate for threshold trust)
    var confirmedKnocks: Int = 0
}

// MARK: - Display Snapshot (SwiftUI-bindable, main-thread only)

/// Value-type snapshot published to the main actor so SwiftUI views update reactively.
struct AdaptiveDisplayState {
    var threshold: Double = 0.05
    var confidence: Double = 0.0
    var isCalibratedEnough: Bool = false
    var noiseMean: Double = 0.005
    var knockMean: Double = 0.12
    var statusDescription: String = "Learning…"
}

// MARK: - Adaptive Threshold Engine

final class AdaptiveThresholdEngine: ObservableObject {

    // MARK: - Published Display State (main-thread, SwiftUI-reactive)

    /// Snapshot updated from the sensor thread via DispatchQueue.main.async.
    /// Use this in SwiftUI views — do NOT read the lock-protected vars directly.
    @Published private(set) var display = AdaptiveDisplayState()

    // MARK: - Internal State (Thread-Safe via stateLock)

    private let stateLock = OSAllocatedUnfairLock()

    private var _threshold: Double = 0.05
    var threshold: Double { stateLock.withLock { _threshold } }

    private var _confidence: Double = 0.0
    var confidence: Double { stateLock.withLock { _confidence } }

    private var _isCalibratedEnough: Bool = false
    var isCalibratedEnough: Bool { stateLock.withLock { _isCalibratedEnough } }

    private var _noiseMean: Double = 0.005
    var noiseMean: Double { stateLock.withLock { _noiseMean } }

    private var _knockMean: Double = 0.12
    var knockMean: Double { stateLock.withLock { _knockMean } }

    private var _state: AdaptiveThresholdState
    var state: AdaptiveThresholdState { stateLock.withLock { _state } }

    // MARK: - Hyper-parameters

    /// Base learning rate for noise updates (α_n) — fast, noise is always present
    private let alphaNoise: Double = 0.015

    /// Base learning rate for knock updates (α_k) — slower, knocks are sparse
    private let alphaKnock: Double = 0.04

    /// Minimum knock-class mean (safety floor so threshold never collapses to 0)
    private let minKnockMean: Double = 0.02

    /// Minimum noise class variance (avoids division by zero)
    private let minVar: Double = 1e-8

    /// Minimum separation ratio: knockMean / noiseMean for calibration flag
    private let minSeparationRatio: Double = 1.8

    /// Samples needed before we trust the model
    private let warmupSamples: Int = 500

    /// Knocks needed before we trust the knock Gaussian
    private let warmupKnocks: Int = 5

    /// How much the session bias shifts the threshold toward recent confirmed knocks
    private let sessionBiasWeight: Double = 0.25

    /// EMA of recent confirmed knock amplitudes (for session bias)
    private var recentKnockEMA: Double = 0.12
    private let recentKnockAlpha: Double = 0.2

    // MARK: - Persistence key

    private let storageKey = "adaptive_threshold_state_v1"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Load persisted state or start fresh
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode(AdaptiveThresholdState.self, from: data) {
            self._state = loaded
        } else {
            self._state = AdaptiveThresholdState()
        }
        recentKnockEMA = _state.knockMean
        refreshPublished()
    }

    // MARK: - Feed

    /// Call this for every candidate detection amplitude (high-pass magnitude at detection time).
    /// `isConfirmedKnock` = true when multiple algorithms agree it's a real knock.
    func feed(amplitude: Double, isConfirmedKnock: Bool) {
        stateLock.withLock {
            _state.samplesSeen += 1

            // --- E-step: compute soft responsibilities ---
            let rKnock = responsibility(x: amplitude,
                                        mean: _state.knockMean,
                                        variance: max(_state.knockVar, minVar),
                                        weight: _state.knockPrior)
            let rNoise = 1.0 - rKnock

            // --- M-step: exponential moving average updates ---
            let alphaN = adaptiveLR(base: alphaNoise, seen: _state.samplesSeen)
            _state.noiseMean = lerp(_state.noiseMean, amplitude, w: alphaN * rNoise)
            let noiseResidual = amplitude - _state.noiseMean
            _state.noiseVar = lerp(_state.noiseVar,
                                  noiseResidual * noiseResidual,
                                  w: alphaN * rNoise)
            _state.noiseVar = max(_state.noiseVar, minVar)

            // Knock class only updated when we're fairly confident it's a knock
            if isConfirmedKnock {
                _state.confirmedKnocks += 1
                recentKnockEMA = lerp(recentKnockEMA, amplitude, w: recentKnockAlpha)

                let alphaK = adaptiveLR(base: alphaKnock, seen: _state.confirmedKnocks)
                _state.knockMean = lerp(_state.knockMean, amplitude, w: alphaK)
                _state.knockMean = max(_state.knockMean, minKnockMean)
                let knockResidual = amplitude - _state.knockMean
                _state.knockVar = lerp(_state.knockVar,
                                      knockResidual * knockResidual,
                                      w: alphaK)
                _state.knockVar = max(_state.knockVar, minVar)

                // Update prior (EMA of observed knock rate, capped)
                _state.knockPrior = min(0.5, lerp(_state.knockPrior, 1.0, w: 0.01))
            } else if amplitude < _threshold {
                // Clearly not a knock — nudge prior slightly down
                _state.knockPrior = max(0.05, lerp(_state.knockPrior, 0.0, w: 0.001))
            }

            // --- Recompute Fisher threshold ---
            recomputeThreshold()
            refreshPublished()

            // Persist every 500 samples (~5 s at normal detection rate)
            if _state.samplesSeen % 500 == 0 {
                saveLocked()
            }
        }
    }

    /// Notify the engine that a knock was positively confirmed by the action system
    /// (i.e., pattern was recognised and action fired). This is the strongest signal.
    func confirmKnock(amplitude: Double) {
        feed(amplitude: amplitude, isConfirmedKnock: true)
    }

    // MARK: - Query

    /// Returns true if amplitude clears the adaptive threshold
    func passes(_ amplitude: Double) -> Bool {
        return amplitude >= threshold
    }

    /// Current calibration status description for UI (reads from the published snapshot).
    var statusDescription: String { display.statusDescription }

    // MARK: - Reset

    func resetLearning() {
        stateLock.withLock {
            _state = AdaptiveThresholdState()
            recentKnockEMA = _state.knockMean
            UserDefaults.standard.removeObject(forKey: storageKey)
            recomputeThreshold()
            refreshPublished()
        }
    }

    // MARK: - Private

    /// Soft responsibility for class with given Gaussian params and prior weight.
    private func responsibility(x: Double, mean: Double, variance: Double, weight: Double) -> Double {
        let noise_prior = 1.0 - weight
        let pKnock = gaussianPDF(x, mean: mean, variance: variance) * weight
        let pNoise = gaussianPDF(x, mean: _state.noiseMean, variance: max(_state.noiseVar, minVar)) * noise_prior
        let total = pKnock + pNoise + 1e-30
        return pKnock / total
    }

    /// Gaussian probability density function
    private func gaussianPDF(_ x: Double, mean: Double, variance: Double) -> Double {
        let v = max(variance, minVar)
        let diff = x - mean
        return exp(-0.5 * diff * diff / v) / sqrt(2 * .pi * v)
    }

    /// Recompute the Fisher 1-D optimal threshold between the two Gaussians,
    /// then blend with session bias toward recent confirmed knock EMA.
    private func recomputeThreshold() {
        let sn = max(_state.noiseVar, minVar)
        let sk = max(_state.knockVar, minVar)
        let mu_n = _state.noiseMean
        let mu_k = max(_state.knockMean, minKnockMean)

        // Fisher variance-weighted midpoint
        let fisherT = (sk * mu_n + sn * mu_k) / (sn + sk)

        // Session bias — pull Fisher threshold toward recent confirmed knock mean
        // so that a user who knocks softly doesn't get blocked by prior priors
        let biasedT = (1.0 - sessionBiasWeight) * fisherT
                    + sessionBiasWeight * (recentKnockEMA * 0.5)

        // Bhattacharyya coefficient (class overlap) → confidence
        let bc = bhattacharyya(mu1: mu_n, var1: sn, mu2: mu_k, var2: sk)
        let sep = max(0, 1.0 - bc)           // 0 = total overlap, 1 = perfect separation
        _confidence = min(1.0, sep)

        // If we haven't warmed up yet, blend toward the fixed fallback (0.05)
        let warmup = _state.confirmedKnocks < warmupKnocks || _state.samplesSeen < warmupSamples
        let blend = warmup ? max(0.0, 1.0 - Double(_state.confirmedKnocks) / Double(warmupKnocks)) : 0.0
        let fallback = 0.05
        _threshold = lerp(biasedT, fallback, w: blend)

        // Clamp to sane range
        _threshold = _threshold.clamped(to: 0.005...0.50)

        // Calibration flag
        let ratio = mu_k / max(mu_n, 1e-6)
        _isCalibratedEnough = !warmup && ratio >= minSeparationRatio && _confidence >= 0.4
    }

    /// Bhattacharyya coefficient between two 1-D Gaussians (in [0, 1])
    /// 1 = complete overlap (bad), 0 = no overlap (perfect separation)
    private func bhattacharyya(mu1: Double, var1: Double, mu2: Double, var2: Double) -> Double {
        let v1 = max(var1, minVar)
        let v2 = max(var2, minVar)
        let meanDiff = mu1 - mu2
        let varSum = (v1 + v2) / 2.0
        let term1 = 0.25 * meanDiff * meanDiff / varSum
        let term2 = 0.5 * log(varSum / sqrt(v1 * v2))
        let bd = term1 + term2  // Bhattacharyya distance
        return exp(-bd)          // Convert to coefficient [0,1]
    }

    /// Adaptive learning rate — decays from base toward base/3 as samples grow,
    /// ensuring early-session fast adaptation and long-term stability.
    private func adaptiveLR(base: Double, seen: Int) -> Double {
        let decay = 1.0 / (1.0 + Double(seen) / 2000.0)
        return base * (0.33 + 0.67 * decay)
    }

    /// Exponential lerp helper: lerp(a, b, w) = a + w*(b-a)
    private func lerp(_ a: Double, _ b: Double, w: Double) -> Double {
        return a + w.clamped(to: 0...1) * (b - a)
    }

    private func refreshPublished() {
        _noiseMean = _state.noiseMean
        _knockMean = _state.knockMean

        // Build a snapshot while still inside the lock (all values consistent),
        // then push it to the main thread so SwiftUI views update reactively.
        let snap = AdaptiveDisplayState(
            threshold: _threshold,
            confidence: _confidence,
            isCalibratedEnough: _isCalibratedEnough,
            noiseMean: _state.noiseMean,
            knockMean: _state.knockMean,
            statusDescription: buildStatusDescription()
        )
        DispatchQueue.main.async { [weak self] in
            self?.display = snap
        }
    }

    /// Builds the status string from already-locked state. Must be called inside stateLock.
    private func buildStatusDescription() -> String {
        if _state.confirmedKnocks < warmupKnocks {
            let remaining = warmupKnocks - _state.confirmedKnocks
            return "Learning… (\(remaining) knock\(remaining == 1 ? "" : "s") to calibrate)"
        } else if _confidence < 0.4 {
            return "Calibrating… (knock harder for better separation)"
        } else {
            return String(format: "Calibrated (%.0f%% confidence)", _confidence * 100)
        }
    }

    private func saveLocked() {
        let stateCopy = _state
        let key = storageKey
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(stateCopy) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

// MARK: - Comparable extension

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
