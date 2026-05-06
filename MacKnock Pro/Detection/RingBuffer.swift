// RingBuffer.swift
// MacKnock Pro
//
// Fixed-size circular buffers for efficient real-time signal processing.
// Ported from the RingFloat types in taigrr/apple-silicon-accelerometer/detector.

import Foundation
import os

// MARK: - Float Ring Buffer

/// Fixed-size circular buffer of Double values for signal processing.
final class RingFloat {
    private var buffer: [Double]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int
    private let lock = OSAllocatedUnfairLock()
    
    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.buffer = [Double](repeating: 0, count: self.capacity)
    }
    
    /// Push a new value, overwriting the oldest if full.
    func push(_ value: Double) {
        lock.withLock {
            buffer[head] = value
            head = (head + 1) % capacity
            if count < capacity {
                count += 1
            }
        }
    }
    
    /// Number of elements currently stored.
    var length: Int { lock.withLock { count } }
    
    /// Whether the buffer is full.
    var isFull: Bool { lock.withLock { count == capacity } }
    
    /// Get the most recently pushed value.
    var last: Double? {
        lock.withLock {
            guard count > 0 else { return nil }
            let idx = (head - 1 + capacity) % capacity
            return buffer[idx]
        }
    }
    
    /// Get value at position (0 = oldest).
    subscript(index: Int) -> Double {
        lock.withLock {
            let start = (head - count + capacity) % capacity
            return buffer[(start + index) % capacity]
        }
    }
    
    /// Return a snapshot as an ordered array (oldest first).
    func slice() -> [Double] {
        lock.withLock {
            guard count > 0 else { return [] }
            var result = [Double](repeating: 0, count: count)
            let start = (head - count + capacity) % capacity
            for i in 0..<count {
                result[i] = buffer[(start + i) % capacity]
            }
            return result
        }
    }
    
    /// Reset the buffer.
    func reset() {
        lock.withLock {
            head = 0
            count = 0
        }
    }
}

// MARK: - Lock-free Ring Buffer (sensor thread only)

/// Same as RingFloat but with no locking. Use ONLY when all access is from
/// a single thread (e.g. the HID sensor callback thread in KnockDetector).
final class UnsafeRingFloat {
    private var buffer: [Double]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.buffer = [Double](repeating: 0, count: self.capacity)
    }

    func push(_ value: Double) {
        buffer[head] = value
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    var length: Int { count }

    func slice() -> [Double] {
        guard count > 0 else { return [] }
        var result = [Double](repeating: 0, count: count)
        let start = (head - count + capacity) % capacity
        for i in 0..<count {
            result[i] = buffer[(start + i) % capacity]
        }
        return result
    }

    func reset() {
        head = 0
        count = 0
    }
}

