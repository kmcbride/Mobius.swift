// Copyright Spotify AB.
// SPDX-License-Identifier: Apache-2.0

import Foundation

final class Lock {
    private let lock: os_unfair_lock_t

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    @discardableResult
    func synchronized<Result>(closure: () throws -> Result) rethrows -> Result {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        return try closure()
    }
}

final class Synchronized<Value> {
    private let lock = Lock()
    private var storage: Value

    init(value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.synchronized { storage }
        }
        set {
            lock.synchronized { storage = newValue }
        }
    }

    func mutate(with closure: (inout Value) throws -> Void) rethrows {
        try lock.synchronized {
            try closure(&storage)
        }
    }

    func read(in closure: (Value) throws -> Void) rethrows {
        try lock.synchronized {
            try closure(storage)
        }
    }
}

extension Synchronized where Value: Equatable {
    func compareAndSwap(expected: Value, with newValue: Value) -> Bool {
        var success = false
        self.mutate { value in
            if value == expected {
                value = newValue
                success = true
            }
        }
        return success
    }
}
