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

import Combine
import Foundation
import MobiusCore

extension Publisher where Failure == Never {
    /// Creates a Mobius event source wrapper around the publisher.
    /// - Returns: A `Mobius.EventSource` wrapping this publisher.
    public func makeEventSource() -> AnyEventSource<Output> {
        return AnyEventSource { consumer in connect(consumer) }
    }
}

extension Subject {
    /// Creates a Mobius connectable wrapper around the subject.
    /// - Parameter consumerPublisher: A publisher whose output is forwarded to the consumer.
    /// - Returns: A `Mobius.Connectable` wrapping this subject.
    public func makeConnectable<ConsumerPublisher: Publisher>(
        with consumerPublisher: ConsumerPublisher
    ) -> AnyConnectable<Output, ConsumerPublisher.Output> where ConsumerPublisher.Failure == Never {
        return AnyConnectable { consumer in
            let consumerDisposable = consumerPublisher.connect(consumer)

            return Connection(
                acceptClosure: { value in self.send(value) },
                disposeClosure: { consumerDisposable.dispose() }
            )
        }
    }
}

extension MobiusController {
    /// Connects an object that will publish model changes and can submit loop events.
    /// - Returns: An `ObservableConnection` instance that emits models and submits events.
    public func connectObservable() -> ObservableConnection<Model, Event> {
        return ObservableConnection(self)
    }
}

/// An object with a publisher that emits loop model changes and a method that submits loop events.
///
/// SwiftUI integrations can extend this object to create bindings for model properties and events.
///
///     extension ObservableConnection {
///         func bind<T>(_ keyPath: KeyPath<Model, T>, event: @escaping (T) -> Event) -> Binding<T> {
///             return Binding(
///                 get: { self.model[keyPath: keyPath] },
///                 set: { value in self.send(event(value)) }
///             )
///         }
///     }
///
///     // Example of binding a model property and change event
///     TextField("Name…", text: connection.bind(\.name, event: { .nameChanged($0) }))
///
public final class ObservableConnection<Model, Event>: ObservableObject {
    @Published public private(set) var model: Model

    private let modelPublisher = PassthroughSubject<Model, Never>()
    private let eventPublisher = PassthroughSubject<Event, Never>()
    private var modelPublisherCancellable: AnyCancellable?

    init<Effect>(_ loopController: MobiusController<Model, Event, Effect>) {
        model = loopController.model
        modelPublisherCancellable = modelPublisher.weakAssign(to: \.model, on: self)

        loopController.connectView(modelPublisher.makeConnectable(with: eventPublisher))
    }

    public func send(_ event: Event) {
        eventPublisher.send(event)
    }
}

private extension Publisher where Failure == Never {
    func connect(_ consumer: @escaping Consumer<Output>) -> Disposable {
        let lock = NSRecursiveLock()
        var isCancelled = false

        let cancellable = sink { output in
            lock.lock()
            defer { lock.unlock() }

            if !isCancelled {
                consumer(output)
            }
        }

        return AnonymousDisposable {
            lock.lock()
            defer { lock.unlock() }

            isCancelled = true
            cancellable.cancel()
        }
    }

    func weakAssign<Root: AnyObject>(
        to keyPath: ReferenceWritableKeyPath<Root, Output>,
        on object: Root
    ) -> AnyCancellable {
        return sink { [weak object] value in object?[keyPath: keyPath] = value }
    }
}
