// HighPassFilter.swift
// MacKnock Pro
//
// Single-pole IIR high-pass filter for real-time gravity removal.
// Matches the approach in taigrr/apple-silicon-accelerometer/detector.

import Foundation

/// Single-pole IIR high-pass filter for removing gravity from accelerometer data.
///
/// Transfer function: y[n] = α * (y[n-1] + x[n] - x[n-1])
/// This effectively removes the DC component (gravity ≈ 1g at rest).
final class HighPassFilter {
    
    /// Filter coefficient (0-1). Higher = less filtering (passes more low-freq).
    /// Default 0.85 gives ~2.8Hz cutoff at 100Hz sample rate.
    let alpha: Double
    
    /// Previous raw input values (x, y, z)
    private var prevRaw: (x: Double, y: Double, z: Double) = (0, 0, 0)
    
    /// Previous filtered output values (x, y, z)
    private var prevOut: (x: Double, y: Double, z: Double) = (0, 0, 0)
    
    /// Whether the filter has been initialized with a first sample
    private var isReady = false
    
    init(alpha: Double = 0.85) {
        self.alpha = alpha
    }
    
    /// Process one 3-axis accelerometer sample.
    /// Returns the high-passed (gravity-removed) values.
    /// First sample returns (0, 0, 0) to prime the filter.
    func process(x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double) {
        if !isReady {
            prevRaw = (x, y, z)
            isReady = true
            return (0, 0, 0)
        }
        
        // IIR high-pass: y = α * (y_prev + x - x_prev)
        let hx = alpha * (prevOut.x + x - prevRaw.x)
        let hy = alpha * (prevOut.y + y - prevRaw.y)
        let hz = alpha * (prevOut.z + z - prevRaw.z)
        
        prevRaw = (x, y, z)
        prevOut = (hx, hy, hz)
        
        return (hx, hy, hz)
    }
    
    /// Reset the filter state.
    func reset() {
        prevRaw = (0, 0, 0)
        prevOut = (0, 0, 0)
        isReady = false
    }
}
