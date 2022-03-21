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

@testable import MobiusExtras

import Combine
import Foundation
import MobiusCore
import Nimble
import Quick

final class CombineTests: QuickSpec {
    private struct Model {
        let name: String
        let age: Int
    }

    private enum Event {
        case nameChanged(String)
        case ageChanged(Int)
    }

    override func spec() {
        let model = Model(name: "", age: 0)
        let loopBuilder: Mobius.Builder<Model, Event, Never> = Mobius.beginnerLoop { model, event in
            switch event {
            case .nameChanged(let name): return Model(name: name, age: model.age)
            case .ageChanged(let age): return Model(name: model.name, age: age)
            }
        }

        describe("PublisherEventSource") {
            let eventPublisher = PassthroughSubject<Event, Never>()

            context("when receiving an event") {
                let loop = loopBuilder
                    .withEventSource(eventPublisher.makeEventSource())
                    .start(from: model)

                it("should forward the event") {
                    eventPublisher.send(.nameChanged("A Name"))
                    expect(loop.latestModel.name).to(equal("A Name"))

                    eventPublisher.send(.ageChanged(21))
                    expect(loop.latestModel.age).to(equal(21))
                }
            }
        }

        describe("SubjectConnectable") {
            let modelSubject = CurrentValueSubject<Model, Never>(model)

            context("when receiving a value") {
                let loop = loopBuilder.start(from: model)
                let eventPublisher = PassthroughSubject<Event, Never>()

                beforeEach {
                    let connectable = modelSubject.makeConnectable(with: eventPublisher)
                    let connection = connectable.connect(loop.dispatchEvent)
                    loop.addObserver(connection.accept)
                }

                it("should forward the value") {
                    eventPublisher.send(.nameChanged("A Name"))
                    expect(modelSubject.value.name).to(equal("A Name"))

                    eventPublisher.send(.ageChanged(21))
                    expect(modelSubject.value.age).to(equal(21))
                }
            }
        }

        describe("ObservableConnection") {
            let loopQueue = DispatchQueue(label: "loop queue")
            let viewQueue = DispatchQueue(label: "view queue")
            let loopController = loopBuilder.makeController(from: model, loopQueue: loopQueue, viewQueue: viewQueue)
            let observableConnection = loopController.connectObservable()

            beforeEach {
                loopController.start()
            }

            context("when submitting events") {
                it("should emit model changes") {
                    observableConnection.send(.nameChanged("A Name"))
                    observableConnection.send(.ageChanged(21))

                    loopQueue.sync {} // Waits until loop work has completed
                    viewQueue.sync {} // Waits until connection work has completed

                    expect(observableConnection.model.name).to(equal("A Name"))
                    expect(observableConnection.model.age).to(equal(21))
                }
            }
        }
    }
}
