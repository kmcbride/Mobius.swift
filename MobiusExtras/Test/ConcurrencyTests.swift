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

#if canImport(_Concurrency) && compiler(>=5.5.2)

import MobiusCore
import MobiusExtras
import Nimble
import Quick

private enum Effect: Equatable {
    case effect
    case effectWithValues(Int, String)
}

private enum Event: Equatable {
    case event
    case eventWithValues(Int, String)
}

class ConcurrencyTests: QuickSpec {
    override func spec() {
        describe("EffectRouterDSL") {
            context("routing to an async handler") {
                var receivedEvents: [Event]!
                var asyncHandler: AsyncEffectHandler!

                beforeEach {
                    receivedEvents = []
                    asyncHandler = AsyncEffectHandler()
                }

                it("supports returning a task producing events") {
                    let dslHandler = EffectRouter<Effect, Event>()
                        .routeCase(Effect.effect).to(asyncHandler.processTask)
                        .routeCase(Effect.effectWithValues).to(asyncHandler.processTaskWithValues)
                        .asConnectable
                        .connect { receivedEvents.append($0) }

                    dslHandler.accept(.effect)
                    expect(receivedEvents).toEventually(equal([.event]))

                    dslHandler.accept(.effectWithValues(1, "S"))
                    expect(receivedEvents).toEventually(equal([.event, .eventWithValues(1, "S")]))
                }

                it("supports returning a single event") {
                    let dslHandler = EffectRouter<Effect, Event>()
                        .routeCase(Effect.effect).to(asyncHandler.processEvent)
                        .routeCase(Effect.effectWithValues).to(asyncHandler.processEventWithValues)
                        .asConnectable
                        .connect { receivedEvents.append($0) }

                    dslHandler.accept(.effect)
                    expect(receivedEvents).toEventually(equal([.event]))

                    dslHandler.accept(.effectWithValues(1, "S"))
                    expect(receivedEvents).toEventually(equal([.event, .eventWithValues(1, "S")]))
                }

                it("supports returning multiple events") {
                    let dslHandler = EffectRouter<Effect, Event>()
                        .routeCase(Effect.effect).to(asyncHandler.processEvents)
                        .routeCase(Effect.effectWithValues).to(asyncHandler.processEventsWithValues)
                        .asConnectable
                        .connect { receivedEvents.append($0) }

                    dslHandler.accept(.effect)
                    expect(receivedEvents).toEventually(equal([.event, .event]))

                    dslHandler.accept(.effectWithValues(1, "S"))
                    expect(receivedEvents).toEventually(equal([.event, .event, .eventWithValues(1, "S"), .eventWithValues(1, "S")]))
                }

                it("supports returning a stream of events") {
                    let dslHandler = EffectRouter<Effect, Event>()
                        .routeCase(Effect.effect).to(asyncHandler.processStream)
                        .routeCase(Effect.effectWithValues).to(asyncHandler.processStreamWithValues)
                        .asConnectable
                        .connect { receivedEvents.append($0) }

                    dslHandler.accept(.effect)
                    expect(receivedEvents).toEventually(equal([.event, .event]))

                    dslHandler.accept(.effectWithValues(1, "S"))
                    expect(receivedEvents).toEventually(equal([.event, .event, .eventWithValues(1, "S"), .eventWithValues(1, "S")]))
                }
            }
        }
    }
}

private struct AsyncEffectHandler {
    func processTask(_ params: Void, callback: EffectCallback<Event>) -> Task<Void, Never> {
        return Task {
            callback.end(with: .event)
        }
    }

    func processTaskWithValues(_ params: (Int, String), callback: EffectCallback<Event>) -> Task<Void, Never> {
        return Task {
            callback.end(with: .eventWithValues(params.0, params.1))
        }
    }

    func processEvent() async -> Event {
        return .event
    }

    func processEventWithValues(_ params: (Int, String)) async -> Event {
        return .eventWithValues(params.0, params.1)
    }

    func processEvents() async -> [Event] {
        return [.event, .event]
    }

    func processEventsWithValues(_ params: (Int, String)) async -> [Event] {
        return [
            .eventWithValues(params.0, params.1),
            .eventWithValues(params.0, params.1),
        ]
    }

    func processStream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            continuation.yield(.event)
            continuation.yield(.event)
            continuation.finish()
        }
    }

    func processStreamWithValues(_ params: (Int, String)) -> AsyncStream<Event> {
        AsyncStream { continuation in
            continuation.yield(.eventWithValues(params.0, params.1))
            continuation.yield(.eventWithValues(params.0, params.1))
            continuation.finish()
        }
    }
}

#endif
