// KnockDetector.swift
// MacKnock Pro
//
// Multi-algorithm vibration/knock detection engine.
// Ported from taigrr/apple-silicon-accelerometer/detector/detector.go
// Implements STA/LTA, CUSUM, Kurtosis, and Peak/MAD detection.

import Foundation
import Combine
import os

// MARK: - Knock Event

/// Severity levels for detected knock events
enum KnockSeverity: String, CaseIterable, Codable {
    case major      = "MAJOR"       // ★ Hard knock (≥4 detectors, amp > 0.05)
    case shock      = "SHOCK"       // ▲ Firm knock (≥3 detectors, amp > 0.02)
    case micro      = "MICRO"       // △ Light tap (PEAK, amp > 0.005)
    case vibration  = "VIBRATION"   // ● Vibration (filtered out)
    case lightVib   = "LIGHT_VIB"   // ○ Light vibration (filtered out)
    case microVib   = "MICRO_VIB"   // · Micro vibration (filtered out)
    
    var symbol: String {
        switch self {
        case .major:    return "★"
        case .shock:    return "▲"
        case .micro:    return "△"
        case .vibration: return "●"
        case .lightVib: return "○"
        case .microVib: return "·"
        }
    }
    
    var label: String {
        switch self {
        case .major:    return "Hard Knock"
        case .shock:    return "Firm Knock"
        case .micro:    return "Light Tap"
        case .vibration: return "Vibration"
        case .lightVib: return "Light Vibration"
        case .microVib: return "Micro Vibration"
        }
    }
    
    /// Whether this severity level represents a real knock (vs. ambient noise)
    var isKnock: Bool {
        switch self {
        case .major, .shock, .micro: return true
        default: return false
        }
    }
}

/// A detected knock/vibration event
struct KnockEvent: Identifiable {
    let id = UUID()
    let time: Date            // Wall-clock time for UI display
    let machTimestamp: Double  // Monotonic mach time in seconds (for internal timing)
    let severity: KnockSeverity
    let amplitude: Double
    let sources: Set<String>
    
    var isKnock: Bool { severity.isKnock }
}

// MARK: - Knock Detector

/// Multi-algorithm knock detection engine that processes accelerometer samples
/// and emits knock events. Combines 4 detection algorithms:
/// 1. STA/LTA (Short-Term Average / Long-Term Average) at 3 timescales
/// 2. CUSUM (Cumulative Sum) for mean-shift detection
/// 3. Kurtosis for impulsive signal detection
/// 4. Peak/MAD (Median Absolute Deviation) for outlier detection
final class KnockDetector: ObservableObject {
    
    // MARK: - Published State
    
    @Published var lastEvent: KnockEvent?
    @Published var isDetecting = false
    
    // Optimization
    private let stateLock = OSAllocatedUnfairLock()
    
    // Non-published stats for UI polling
    private var _currentMagnitude: Double = 0
    var currentMagnitude: Double { stateLock.withLock { _currentMagnitude } }
    
    private var _currentRMS: Double = 0
    var currentRMS: Double { stateLock.withLock { _currentRMS } }
    
    /// Closure called when a confirmed knock event occurs
    var onKnock: ((KnockEvent) -> Void)?
    
    // MARK: - Configuration

    /// Adaptive ML threshold engine — the primary gate for knock classification.
    /// Updated on every detected amplitude; replaces fixed minAmplitude.
    let adaptiveThreshold = AdaptiveThresholdEngine()

    /// Hard minimum floor — the adaptive threshold will never go below this.
    /// Acts as a user-settable safety net (settings slider).
    var amplitudeFloor: Double = 0.01

    /// Current effective threshold (adaptive or floor, whichever is larger)
    var currentThreshold: Double {
        max(adaptiveThreshold.threshold, amplitudeFloor)
    }

    /// Debounce period between individual knock events (prevents same physical
    /// knock from triggering multiple events via multi-algorithm detection).
    /// This must be SHORT (< intra-knock window) so rapid successive knocks
    /// can still reach the pattern recognizer.
    var knockDebounce: TimeInterval = 0.08

    /// Sample rate in Hz
    let sampleRate: Int = 100
    
    // MARK: - Internal State
    
    private var sampleCount = 0
    // Alpha 0.85 gives ~2.8Hz high-pass cutoff (at 100Hz fps), which is crucial
    // to filter out the 1-2Hz macro movements from picking up or moving the laptop.
    // (Previous 0.95 allowed 0.8Hz movements to leak through as knocks).
    private let highPassFilter = HighPassFilter(alpha: 0.85)
    
    // Waveform history (magnitude only; read by UI via .slice())
    let waveform: RingFloat
    
    // STA/LTA detector (3 timescales)
    private var sta: [Double] = [0, 0, 0]
    private var lta: [Double] = [1e-10, 1e-10, 1e-10]
    private let staN: [Int] = [3, 15, 50]
    private let ltaN: [Int] = [100, 500, 2000]
    private let staLTAOn: [Double] = [3.0, 2.5, 2.0]
    private let staLTAOff: [Double] = [1.5, 1.3, 1.2]
    private var staLTAActive: [Bool] = [false, false, false]
    private var staLTALatest: [Double] = [1.0, 1.0, 1.0]
    
    // CUSUM
    private var cusumPos: Double = 0
    private var cusumNeg: Double = 0
    private var cusumMu: Double = 0
    private let cusumK: Double = 0.0005
    private let cusumH: Double = 0.01
    
    // Kurtosis (sensor-thread only — no lock needed)
    private let kurtBuf: UnsafeRingFloat
    private var kurtosis: Double = 3.0
    private var kurtDecimation = 0

    // Peak / MAD / Crest factor (sensor-thread only — no lock needed)
    private let peakBuf: UnsafeRingFloat
    private var crest: Double = 1.0
    private var rms: Double = 0
    private var peak: Double = 0
    private var madSigma: Double = 0

    // RMS trend (sensor-thread only — no lock needed)
    private let rmsTrend: UnsafeRingFloat
    private let rmsWindow: UnsafeRingFloat
    private var rmsDecimation = 0
    
    // Event history
    private var _events: [KnockEvent] = []
    var events: [KnockEvent] { stateLock.withLock { _events } }
    private var lastEventTime: Double = 0
    private var lastKnockTimestamp: Double = 0
    
    // Optimization
    private var quietCounter: Int = 0
    
    // MARK: - Init
    
    init() {
        let n5 = sampleRate * 5
        waveform = RingFloat(capacity: n5)
        kurtBuf = UnsafeRingFloat(capacity: 100)
        peakBuf = UnsafeRingFloat(capacity: 200)
        rmsTrend = UnsafeRingFloat(capacity: 100)
        rmsWindow = UnsafeRingFloat(capacity: sampleRate)
    }
    
    // MARK: - Processing
    
    /// Process one accelerometer sample. Returns the gravity-removed magnitude.
    @discardableResult
    func process(ax: Double, ay: Double, az: Double, time: Double) -> Double {
        sampleCount += 1
        
        // High-pass filter for gravity removal
        let hp = highPassFilter.process(x: ax, y: ay, z: az)
        let mag = sqrt(hp.x * hp.x + hp.y * hp.y + hp.z * hp.z)
        
        stateLock.withLock { _currentMagnitude = mag }
        waveform.push(mag)
        
        // RMS trend tracking
        rmsWindow.push(mag)
        rmsDecimation += 1
        if rmsDecimation >= max(1, sampleRate / 10) {
            rmsDecimation = 0
            let vals = rmsWindow.slice()
            if !vals.isEmpty {
                let sumSq = vals.reduce(0.0) { $0 + $1 * $1 }
                rmsTrend.push(sqrt(sumSq / Double(vals.count)))
            }
        }
        
        // Run all detectors
        var detections = Set<String>()
        var anyActive = false
        
        // 1. STA/LTA (3 timescales)
        let energy = mag * mag
        for i in 0..<3 {
            sta[i] += (energy - sta[i]) / Double(staN[i])
            lta[i] += (energy - lta[i]) / Double(ltaN[i])
            let ratio = sta[i] / (lta[i] + 1e-30)
            staLTALatest[i] = ratio
            let wasActive = staLTAActive[i]
            if ratio > staLTAOn[i] && !wasActive {
                staLTAActive[i] = true
                detections.insert("STA/LTA")
            } else if ratio < staLTAOff[i] {
                staLTAActive[i] = false
            }
            if ratio > staLTAOff[i] {
                anyActive = true
            }
        }
        
        if anyActive {
            quietCounter = 0
        } else {
            quietCounter += 1
        }
        
        let isQuiet = quietCounter > 500
        
        if !isQuiet {
            // 2. CUSUM
            cusumMu += 0.0001 * (mag - cusumMu)
            cusumPos = max(0, cusumPos + mag - cusumMu - cusumK)
            cusumNeg = max(0, cusumNeg - mag + cusumMu - cusumK)
            if cusumPos > cusumH {
                detections.insert("CUSUM")
                cusumPos = 0
            }
            if cusumNeg > cusumH {
                detections.insert("CUSUM")
                cusumNeg = 0
            }
            
            // 3. Kurtosis
            kurtBuf.push(mag)
            kurtDecimation += 1
            if kurtDecimation >= 10 && kurtBuf.length >= 50 {
                kurtDecimation = 0
                let buf = kurtBuf.slice()
                let n = Double(buf.count)
                let mean = buf.reduce(0, +) / n
                var m2: Double = 0
                var m4: Double = 0
                for v in buf {
                    let diff = v - mean
                    let d2 = diff * diff
                    m2 += d2
                    m4 += d2 * d2
                }
                m2 /= n
                m4 /= n
                kurtosis = m4 / (m2 * m2 + 1e-30)
                if kurtosis > 6 {
                    detections.insert("KURTOSIS")
                }
            }
            
            // 4. Peak / MAD
            peakBuf.push(mag)
            if peakBuf.length >= 50 && sampleCount % 10 == 0 {
                let buf = peakBuf.slice()
                let sorted = buf.sorted()
                let n = sorted.count
                let median = sorted[n / 2]
                
                // MAD (Median Absolute Deviation)
                let deviations = sorted.map { abs($0 - median) }.sorted()
                let mad = deviations[n / 2]
                let sigma = 1.4826 * mad + 1e-30
                madSigma = sigma
                
                // RMS and Peak
                var sumSq: Double = 0
                var pk: Double = 0
                for v in buf {
                    sumSq += v * v
                    if abs(v) > pk { pk = abs(v) }
                }
                rms = sqrt(sumSq / Double(n))
                peak = pk
                crest = pk / (rms + 1e-30)
                stateLock.withLock { _currentRMS = rms }
                
                // Outlier detection
                let dev = abs(mag - median) / sigma
                if dev > 2.0 {
                    detections.insert("PEAK")
                }
            }
        }
        
        // Classify and emit event
        if !detections.isEmpty && (time - lastEventTime) > 0.01 {
            lastEventTime = time
            let event = classify(detections: detections, time: time, amplitude: mag)
            let thresholdAtEvent = currentThreshold
            let passesEvidenceGate = hasSufficientKnockEvidence(
                sources: event.sources,
                amplitude: event.amplitude,
                threshold: thresholdAtEvent
            )
            
            stateLock.withLock {
                _events.append(event)
                if _events.count > 500 {
                    _events.removeFirst(_events.count - 500)
                }
            }

            // Feed amplitude into the adaptive engine on every candidate event.
            // isConfirmedKnock = true when ≥2 independent detectors agree AND
            // the event passes even the current (possibly-uncalibrated) threshold.
            let isPresumedKnock = event.isKnock
                && event.amplitude >= amplitudeFloor
                && passesEvidenceGate
            adaptiveThreshold.feed(amplitude: event.amplitude, isConfirmedKnock: isPresumedKnock)

            // Gate: pass knock only if adaptive threshold AND debounce are satisfied.
            // NOTE: We use a SHORT debounce here (not the user-facing cooldown).
            // The user-facing cooldown is applied at the pattern recognizer level
            // so that individual knocks within a pattern are not blocked.
            if event.isKnock && event.amplitude >= thresholdAtEvent && passesEvidenceGate {
                if (time - lastKnockTimestamp) >= knockDebounce {
                    lastKnockTimestamp = time
                    DispatchQueue.main.async { [weak self] in
                        self?.lastEvent = event
                    }
                    onKnock?(event)
                }
            }
        }
        
        return mag
    }
    
    // MARK: - Classification
    
    /// Classify detection sources and amplitude into a severity level.
    /// Matches the classification logic from detector.go classify().
    private func classify(detections: Set<String>, time: Double, amplitude: Double) -> KnockEvent {
        let ns = detections.count
        
        let severity: KnockSeverity
        switch true {
        case ns >= 3 && amplitude > 0.05:
            severity = .major
        case ns >= 2 && amplitude > 0.02:
            severity = .shock
        case detections.contains("PEAK") && amplitude > 0.005 && (kurtosis > 3.5 || crest > 2.0):
            severity = .micro
        case (detections.contains("STA/LTA") || detections.contains("CUSUM")) && amplitude > 0.003:
            severity = .vibration
        case amplitude > 0.001:
            severity = .lightVib
        default:
            severity = .microVib
        }
        
        return KnockEvent(
            time: Date(),
            machTimestamp: time,
            severity: severity,
            amplitude: amplitude,
            sources: detections
        )
    }

    /// Require multi-signal agreement for low/mid knock amplitudes to reduce
    /// false positives from isolated peak outliers, while still allowing hard
    /// impacts through even with partial detector agreement.
    private func hasSufficientKnockEvidence(
        sources: Set<String>,
        amplitude: Double,
        threshold: Double
    ) -> Bool {
        // 1) Fast structural check: Exclude pure macro-movements (laptop lift)
        if crest < 2.0 && kurtosis < 3.0 {
            return false // Too continuous to be a real knock
        }
        
        let detectorCount = sources.count
        let hasImpulseSignal = sources.contains("STA/LTA") || sources.contains("KURTOSIS") || sources.contains("PEAK")

        // 2) If the signal is prominent and survived the structural check, let it pass
        if amplitude >= max(threshold * 1.2, 0.04) {
            return true
        }

        // 3) Normal gate
        return detectorCount >= 2 && hasImpulseSignal
    }
    
    // MARK: - Lifecycle
    
    /// Starts detection
    func start() {
        isDetecting = true
    }
    
    /// Stops detection
    func stop() {
        isDetecting = false
    }
    
    /// Reset all detector state.
    func reset() {
        highPassFilter.reset()
        waveform.reset()
        kurtBuf.reset()
        peakBuf.reset()
        rmsTrend.reset()
        rmsWindow.reset()
        
        sta = [0, 0, 0]
        lta = [1e-10, 1e-10, 1e-10]
        staLTAActive = [false, false, false]
        staLTALatest = [1.0, 1.0, 1.0]
        cusumPos = 0
        cusumNeg = 0
        cusumMu = 0
        kurtosis = 3.0
        crest = 1.0
        rms = 0
        peak = 0
        madSigma = 0
        
        sampleCount = 0
        quietCounter = 0
        lastEventTime = 0
        lastKnockTimestamp = 0
        stateLock.withLock { _events.removeAll() }
    }

    /// Reset only the adaptive ML model (keeps waveform/detection history).
    func resetAdaptiveModel() {
        adaptiveThreshold.resetLearning()
    }
}
