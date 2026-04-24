// RingBuffer.swift
// MacKnock Pro
//
// Fixed-size circular buffers for efficient real-time signal processing.
// Ported from the RingFloat/RingVec3 types in taigrr/apple-silicon-accelerometer/detector.

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

// MARK: - Vec3 Ring Buffer

/// A 3-axis vector sample for the ring buffer.
struct Vec3 {
    let x: Double
    let y: Double
    let z: Double
}

/// Fixed-size circular buffer of Vec3 values.
final class RingVec3 {
    private var buffer: [Vec3]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int
    private let lock = OSAllocatedUnfairLock()
    
    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.buffer = [Vec3](repeating: Vec3(x: 0, y: 0, z: 0), count: self.capacity)
    }
    
    /// Push a new 3-axis value.
    func push(_ v: Vec3) {
        lock.withLock {
            buffer[head] = v
            head = (head + 1) % capacity
            if count < capacity {
                count += 1
            }
        }
    }
    
    /// Push individual x/y/z components.
    func push(x: Double, y: Double, z: Double) {
        push(Vec3(x: x, y: y, z: z))
    }
    
    /// Number of elements stored.
    var length: Int { lock.withLock { count } }
    
    /// Return a snapshot as ordered array (oldest first).
    func slice() -> [Vec3] {
        lock.withLock {
            guard count > 0 else { return [] }
            var result = [Vec3](repeating: Vec3(x: 0, y: 0, z: 0), count: count)
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
