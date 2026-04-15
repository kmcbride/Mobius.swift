// Copyright Spotify AB.
// SPDX-License-Identifier: Apache-2.0

final class ThreadSafeConnectable<Event, Effect>: Connectable {
    private let connectable: AnyConnectable<Effect, Event>

    private let lock = Lock()
    private var output: Consumer<Event>?
    private var connection: Connection<Effect>?

    init<Conn: Connectable>(
        connectable: Conn
    ) where Conn.Input == Effect, Conn.Output == Event {
        self.connectable = AnyConnectable(connectable)
    }

    func connect(_ consumer: @escaping Consumer<Event>) -> Connection<Effect> {
        let needsConnection = lock.synchronized {
            guard output == nil else {
                return false
            }

            output = consumer

            return true
        }

        guard needsConnection else {
            MobiusHooks.errorHandler(
                "Connection limit exceeded: The Connectable \(type(of: self)) is already connected. " +
                "Unable to connect more than once",
                #file,
                #line
            )
        }

        let innerConnection = connectable.connect(dispatch)
        lock.synchronized { connection = innerConnection }

        return Connection(
            acceptClosure: accept,
            disposeClosure: dispose
        )
    }

    private func accept(_ effect: Effect) {
        if let connection = lock.synchronized(closure: { connection }) {
            connection.accept(effect)
        }
    }

    private func dispatch(event: Event) {
        if let output = lock.synchronized(closure: { output }) {
            output(event)
        }
    }

    private func dispose() {
        var disposeConnection: (() -> Void)?
        lock.synchronized {
            output = nil
            disposeConnection = connection?.dispose
            connection = nil
        }
        disposeConnection?()
    }

    deinit {
        dispose()
    }
}
