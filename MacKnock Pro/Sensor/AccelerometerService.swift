// AccelerometerService.swift
// MacKnock Pro
//
// High-level service that manages accelerometer data streaming.
// Runs IOKit HID on a dedicated thread with CFRunLoop, publishes
// samples via Combine for consumption by the detection engine.

import Foundation
import Combine
import IOKit
import IOKit.hid
import os

final class CallbackBox: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var _callback: ((Double, Double, Double, Double) -> Void)?
    
    func set(_ callback: ((Double, Double, Double, Double) -> Void)?) {
        os_unfair_lock_lock(&lock)
        _callback = callback
        os_unfair_lock_unlock(&lock)
    }
    
    func get() -> ((Double, Double, Double, Double) -> Void)? {
        os_unfair_lock_lock(&lock)
        let cb = _callback
        os_unfair_lock_unlock(&lock)
        return cb
    }
}

/// High-level accelerometer service that manages the IOKit connection
/// and publishes sensor samples via Combine.
@MainActor
final class AccelerometerService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isRunning = false
    @Published var isAvailable = false
    @Published var errorMessage: String?
    @Published var samplesPerSecond: Double = 0
    
    // MARK: - Private State (main-actor isolated)
    
    private var sensorThread: Thread?
    private var hidDevice: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    
    // MARK: - Thread-safe state (accessed from sensor thread)
    
    /// Atomic flag to signal the sensor loop to stop
    private let _shouldStop = OSAllocatedUnfairLock(initialState: false)
    
    /// Callback to process a sample inline on the sensor thread
    private let _onSample = CallbackBox()
    
    /// Decimation state, accessed from the sensor callback thread
    private let _decimationState = OSAllocatedUnfairLock(initialState: DecimationState())
    
    private struct DecimationState {
        var counter: Int = 0
        var factor: Int = SPUConstants.defaultDecimation
        var rateCount: Int = 0
        var lastRateTime: Double = 0
    }
    
    /// Shared instance (singleton since we only have one accelerometer)
    static let shared = AccelerometerService()
    
    // MARK: - Init
    
    nonisolated init(decimation: Int = SPUConstants.defaultDecimation) {
        _decimationState.withLock { $0.factor = decimation }
        
        // Check availability (no root needed)
        let available = IOKitBridge.isAccelerometerAvailable()
        Task { @MainActor in
            self.isAvailable = available
        }
    }
    
    // MARK: - Public API
    
    nonisolated func setCallback(_ callback: @escaping (Double, Double, Double, Double) -> Void) {
        _onSample.set(callback)
    }
    
    /// Start reading accelerometer data. Requires root privileges.
    func start() {
        guard !isRunning else { return }
        guard isAvailable else {
            errorMessage = "Accelerometer not found. Make sure you're on an Apple Silicon Mac (M2+)."
            return
        }
        
        _shouldStop.withLock { $0 = false }
        errorMessage = nil
        
        // Check for root privileges
        guard geteuid() == 0 else {
            errorMessage = "Root privileges required for accelerometer access. Run with sudo."
            return
        }
        
        // Start sensor on a dedicated thread (CFRunLoop requirement)
        let thread = Thread { [weak self] in
            self?.sensorWorkerLoop()
        }
        thread.name = "com.macknockpro.sensor"
        thread.qualityOfService = .utility
        thread.start()
        sensorThread = thread
        
        isRunning = true
    }
    
    /// Stop reading accelerometer data.
    func stop() {
        _shouldStop.withLock { $0 = true }
        isRunning = false
    }
    
    /// Check sensor availability without root
    nonisolated func checkAvailability() -> Bool {
        return IOKitBridge.isAccelerometerAvailable()
    }
    
    /// Get sensor device information
    nonisolated func deviceInfo() -> [String: Any] {
        return IOKitBridge.getDeviceInfo()
    }
    
    // MARK: - Sensor Worker (runs on dedicated thread)
    
    private nonisolated func sensorWorkerLoop() {
        // Wake the SPU drivers first
        IOKitBridge.wakeSPUDrivers()
        
        // Create a context pointer to self for the C callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        // Open the accelerometer device
        guard let result = IOKitBridge.openAccelerometer(
            callback: accelerometerReportCallback,
            context: context
        ) else {
            Task { @MainActor [weak self] in
                self?.errorMessage = "Failed to open accelerometer device. Ensure root privileges."
                self?.isRunning = false
            }
            return
        }
        
        // Store references for cleanup
        let device = result.device
        let buffer = result.reportBuffer
        
        Task { @MainActor [weak self] in
            self?.hidDevice = device
            self?.reportBuffer = buffer
        }
        
        // Run the CFRunLoop — this blocks and processes HID callbacks
        while !_shouldStop.withLock({ $0 }) {
            let runResult = CFRunLoopRunInMode(.defaultMode, 0.5, false)
            if runResult == .finished || runResult == .stopped {
                break
            }
        }
        
        // Cleanup
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
        
        Task { @MainActor [weak self] in
            self?.hidDevice = nil
            self?.reportBuffer = nil
            self?.isRunning = false
        }
    }
    
    /// Called from the C callback on the sensor thread
    nonisolated func handleReport(x: Int32, y: Int32, z: Int32, timestamp: UInt64) {
        let timeSecs = Double(timestamp) * IOKitBridge.machToSeconds
        
        let (shouldProcess, currentRate) = _decimationState.withLock { state -> (Bool, Double?) in
            var rate: Double? = nil
            state.rateCount += 1
            if state.lastRateTime == 0 {
                state.lastRateTime = timeSecs
            } else if timeSecs - state.lastRateTime >= 1.0 {
                rate = Double(state.rateCount) / (timeSecs - state.lastRateTime)
                state.rateCount = 0
                state.lastRateTime = timeSecs
            }
            
            state.counter += 1
            if state.counter < state.factor {
                return (false, rate)
            }
            state.counter = 0
            return (true, rate)
        }
        
        if let currentRate = currentRate {
            Task { @MainActor [weak self] in
                self?.samplesPerSecond = currentRate
            }
        }
        
        guard shouldProcess else { return }
        
        // Convert to physical units
        let ax = Double(x) / SPUConstants.accelScale
        let ay = Double(y) / SPUConstants.accelScale
        let az = Double(z) / SPUConstants.accelScale
        
        // Execute callback inline on sensor thread
        if let callback = _onSample.get() {
            callback(ax, ay, az, timeSecs)
        }
    }
}

// MARK: - C Callback (IOHIDReportWithTimeStampCallback)

/// Global C callback function for IOKit HID input report with timestamp.
/// This is called on the sensor thread whenever a new HID report arrives.
private func accelerometerReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex,
    timestamp: UInt64
) {
    guard let context = context else { return }
    
    // Get the AccelerometerService instance from context
    let service = Unmanaged<AccelerometerService>.fromOpaque(context).takeUnretainedValue()
    
    // Parse the report
    guard let parsed = IOKitBridge.parseIMUReport(report: report, length: Int(reportLength)) else {
        return
    }
    
    // Forward to the service
    service.handleReport(x: parsed.x, y: parsed.y, z: parsed.z, timestamp: timestamp)
}
