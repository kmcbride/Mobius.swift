// Copyright 2019-2022 Spotify AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// A `MobiusLoop` with queue management.
/// It supports starting, stopping, and attaching a variable number of `Connectable`s.
public final class MobiusManagedLoop<Model, Event, Effect> {
    private enum State {
        case stopped
        case starting
        case started
        case stopping
    }

    private let effectHandler: AnyConnectable<Effect, Event>
    private let eventSource: AnyEventSource<Event>
    private let initiate: Initiate<Model, Effect>

    private let queue: DispatchQueue
    private let state: Synchronized<State>

    private var model: Model
    private var connectables: [UUID: AsyncDispatchQueueConnectable<Model, Event>] = [:]
    private var connections: [UUID: Connection<Model>] = [:]

    private var effectConnection: Connection<Effect>!
    private var eventConsumer: Consumer<Event>!
    private var eventSourceDisposable: Disposable!

    init(
        model initialModel: Model,
        update: Update<Model, Event, Effect>,
        eventSource: AnyEventSource<Event>,
        effectHandler: AnyConnectable<Effect, Event>,
        logger: AnyMobiusLogger<Model, Event, Effect>,
        targetQueue: DispatchQueue,
        initiate: Initiate<Model, Effect>? = nil
    ) {
        self.effectHandler = effectHandler
        self.eventSource = eventSource
        self.initiate = logger.wrap(initiate: initiate ?? { First(model: $0) })

        model = initialModel

        queue = .init(label: "ManagedLoop.\(Model.self)", target: targetQueue)
        state = .init(value: .stopped)

        let loggingUpdate = logger.wrap(update: update.updateClosure)
        eventConsumer = { [unowned self] event in
            queue.async {
                guard isRunning else {
                    return
                }

                let next = loggingUpdate(model, event)

                if let nextModel = next.model {
                    model = nextModel
                    connections.values.forEach { $0.accept(nextModel) }
                }

                next.effects.forEach { effectConnection.accept($0) }
            }
        }
    }

    deinit {
        if isRunning {
            stop()
        }
    }

    public var isRunning: Bool { state.value != .stopped }

    @discardableResult
    public func connect<LoopConnectable: Connectable>(
        _ connectable: LoopConnectable,
        acceptQueue: DispatchQueue = .main
    ) -> Disposable where LoopConnectable.Input == Model, LoopConnectable.Output == Event {
        dispatchPrecondition(condition: .notOnQueue(queue))

        let id = UUID()
        let connectable = AsyncDispatchQueueConnectable(connectable, acceptQueue: acceptQueue)

        queue.sync {
            connectables[id] = connectable

            if isRunning {
                connect(connectable, id: id)
            }
        }

        return AnonymousDisposable { [weak self] in
            self?.disconnect(id)
        }
    }

    public func start() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        do {
            try queue.sync {
                guard !isRunning else {
                    throw ErrorMessage(message: "\(Self.debugTag): cannot start while running")
                }

                state.value = .starting

                let first = initiate(model)

                model = first.model
                connectables.forEach { connect($0.value, id: $0.key) }
                effectConnection = effectHandler.connect(eventConsumer)
                eventSourceDisposable = eventSource.subscribe(consumer: eventConsumer)
                first.effects.forEach { effectConnection.accept($0) }

                state.value = .started
            }
        } catch {
            MobiusHooks.errorHandler(error.localizedDescription, #file, #line)
        }
    }

    public func stop() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        do {
            try queue.sync {
                guard isRunning else {
                    throw ErrorMessage(message: "\(Self.debugTag): cannot stop while not running")
                }

                state.value = .stopping

                connections.values.forEach { $0.dispose() }
                connections.removeAll()

                effectConnection.dispose()
                effectConnection = nil

                eventSourceDisposable.dispose()
                eventSourceDisposable = nil

                state.value = .stopped
            }
        } catch {
            MobiusHooks.errorHandler(error.localizedDescription, #file, #line)
        }
    }

    public func dispatchEvent(_ event: Event) {
        eventConsumer(event)
    }

    public func replaceModel(_ newModel: Model) {
        dispatchPrecondition(condition: .notOnQueue(queue))
        do {
            try queue.sync {
                guard !isRunning else {
                    throw ErrorMessage(message: "\(Self.debugTag): cannot replace model while running")
                }

                model = newModel
            }
        } catch {
            MobiusHooks.errorHandler(error.localizedDescription, #file, #line)
        }
    }

    public var latestModel: Model {
        dispatchPrecondition(condition: .notOnQueue(queue))

        return queue.sync { model }
    }

    private func connect(_ connectable: AsyncDispatchQueueConnectable<Model, Event>, id: UUID) {
        let connection = connectable.connect { [unowned self] event in
            eventConsumer(event)
        }
        connections[id] = connection

        connection.accept(model)
    }

    private func disconnect(_ id: UUID) {
        dispatchPrecondition(condition: .notOnQueue(queue))

        queue.sync {
            connectables[id] = nil

            if isRunning, let connection = connections[id] {
                connection.dispose()
                connections[id] = nil
            }
        }
    }
}

private extension MobiusManagedLoop {
    static var debugTag: String { "ManagedLoop<\(Model.self), \(Event.self), \(Effect.self)>" }

    struct ErrorMessage: Error {
        let message: String
        var localizedDescription: String { message }
    }
}
