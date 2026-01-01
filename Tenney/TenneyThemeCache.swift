//
//  TenneyThemeCache.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/31/25.
//


//
//  TenneyThemeCache.swift
//  Tenney
//
//  Strict bounded caching (LRU) for:
//  - ResolvedTenneyTheme per (themeID × scheme × mixBasis × mixMode × scopeMode)
//  - RatioSignature → Color per same key space
//

import Foundation
import SwiftUI

final class TenneyThemeCache {
    static let shared = TenneyThemeCache()

    private let lock = NSLock()

    // Targets (bounded)
    private let resolvedCap = 64
    private let ratioCap = 2048

    private let resolvedLRU = LRU<ResolvedKey, ResolvedTenneyTheme>(capacity: 64)
    private let ratioLRU = LRU<RatioKey, Color>(capacity: 2048)

    struct ResolvedKey: Hashable {
        let themeIDRaw: String
        let schemeIsDark: Bool
        let mixBasis: String
        let mixMode: String
        let scopeMode: String
    }

    struct RatioKey: Hashable {
        let resolved: ResolvedKey
        let sig: RatioSignature
    }

    func getResolved(_ key: ResolvedKey) -> ResolvedTenneyTheme? {
        lock.lock(); defer { lock.unlock() }
        return resolvedLRU.get(key)
    }

    func setResolved(_ value: ResolvedTenneyTheme, for key: ResolvedKey) {
        lock.lock(); defer { lock.unlock() }
        resolvedLRU.set(value, for: key)
    }

    func getRatioColor(_ key: RatioKey) -> Color? {
        lock.lock(); defer { lock.unlock() }
        return ratioLRU.get(key)
    }

    func setRatioColor(_ value: Color, for key: RatioKey) {
        lock.lock(); defer { lock.unlock() }
        ratioLRU.set(value, for: key)
    }
}

// MARK: - Minimal LRU
private final class LRU<Key: Hashable, Value> {
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private let capacity: Int
    private var map: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: Key) -> Value? {
        guard let n = map[key] else { return nil }
        moveToFront(n)
        return n.value
    }

    func set(_ value: Value, for key: Key) {
        if let n = map[key] {
            n.value = value
            moveToFront(n)
            return
        }

        let n = Node(key: key, value: value)
        map[key] = n
        insertAtFront(n)

        if map.count > capacity {
            evictTail()
        }
    }

    private func insertAtFront(_ n: Node) {
        n.prev = nil
        n.next = head
        head?.prev = n
        head = n
        if tail == nil { tail = n }
    }

    private func moveToFront(_ n: Node) {
        guard head !== n else { return }
        // detach
        n.prev?.next = n.next
        n.next?.prev = n.prev

        if tail === n { tail = n.prev }

        // insert
        n.prev = nil
        n.next = head
        head?.prev = n
        head = n
    }

    private func evictTail() {
        guard let t = tail else { return }
        map.removeValue(forKey: t.key)

        if head === t {
            head = nil
            tail = nil
            return
        }

        tail = t.prev
        tail?.next = nil
    }
}
