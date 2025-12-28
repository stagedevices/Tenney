//
//  ScopeRingBuffer.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/28/25.
//


import Foundation
import simd

/// Locking is fine here: producer is audio callback, consumer is MTKView draw.
/// Small payload, low contention.
final class ScopeRingBuffer {
    private let lock = NSLock()
    private var buf: [SIMD2<Float>]
    private var writeIndex: Int = 0
    private var filled: Bool = false

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(64, capacity)
        self.buf = Array(repeating: SIMD2<Float>(0, 0), count: self.capacity)
    }

    func push(x: UnsafePointer<Float>, y: UnsafePointer<Float>, count: Int) {
        lock.lock()
        for i in 0..<count {
            buf[writeIndex] = SIMD2<Float>(x[i], y[i])
            writeIndex += 1
            if writeIndex >= capacity {
                writeIndex = 0
                filled = true
            }
        }
        lock.unlock()
    }

    /// Returns newest `max` points, ordered oldest -> newest (good for lineStrip).
    func snapshot(max: Int) -> [SIMD2<Float>] {
        lock.lock()
        let n = Swift.min(Swift.max(0, max), filled ? capacity : writeIndex)
        guard n > 0 else { lock.unlock(); return [] }

        let end = writeIndex
        let start = (end - n + capacity) % capacity

        var out: [SIMD2<Float>] = []
        out.reserveCapacity(n)

        if start < end {
            out.append(contentsOf: buf[start..<end])
        } else {
            out.append(contentsOf: buf[start..<capacity])
            out.append(contentsOf: buf[0..<end])
        }

        lock.unlock()
        return out
    }
}
