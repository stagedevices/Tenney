//
//  FloatRingBuffer.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/29/25.
//


import Foundation

final class FloatRingBuffer {
    private var buf: [Float]
    private var writeIndex: Int = 0
    private var filled: Bool = false
    private let lock = NSLock()

    init(capacity: Int) {
        buf = [Float](repeating: 0, count: max(1, capacity))
    }

    func push(_ x: [Float]) {
        lock.lock(); defer { lock.unlock() }
        for v in x {
            buf[writeIndex] = v
            writeIndex += 1
            if writeIndex >= buf.count {
                writeIndex = 0
                filled = true
            }
        }
    }

    func readLatest(count n: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let n = max(0, min(n, filled ? buf.count : writeIndex))
        guard n > 0 else { return [] }

        var out = [Float](repeating: 0, count: n)
        let end = writeIndex
        var start = end - n
        if start < 0 { start += buf.count }

        if start < end {
            out[0..<n] = buf[start..<end]
        } else {
            let a = buf.count - start
            out[0..<a] = buf[start..<buf.count]
            out[a..<n] = buf[0..<end]
        }
        return out
    }
}
