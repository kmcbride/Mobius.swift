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

@testable import MobiusCore

import Foundation
import Nimble
import Quick

// swiftlint:disable type_body_length file_length

class MobiusManagedLoopTests: QuickSpec {
    let loopQueue = DispatchQueue(label: "loop queue")
    let connectableQueue = DispatchQueue(label: "connectable queue")

    // swiftlint:disable function_body_length
    override func spec() {
        describe("MobiusManagedLoop") {
            var loop: MobiusManagedLoop<String, String, String>!
            var connectable: RecordingTestConnectable!
            var eventSource: TestEventSource<String>!
            var effectHandler: RecordingTestConnectable!
            var activateInitiator: Bool!

            func clearConnectableRecorder() {
                makeSureAllEffectsAndEventsHaveBeenProcessed()
                connectable.recorder.clear()
            }

            beforeEach {
                connectable = RecordingTestConnectable(expectedQueue: self.connectableQueue)

                let loopQueue = self.loopQueue
                let update = Update<String, String, String> { model, event in
                    dispatchPrecondition(condition: .onQueue(loopQueue))
                    return .next("\(model)-\(event)")
                }

                activateInitiator = false
                let initiate: Initiate<String, String> = { model in
                    if activateInitiator {
                        return First(model: "\(model)-init", effects: ["initEffect"])
                    } else {
                        return First(model: model)
                    }
                }

                eventSource = TestEventSource()
                effectHandler = RecordingTestConnectable()

                loop = Mobius
                    .loop(update: update, effectHandler: effectHandler)
                    .withEventSource(eventSource)
                    .makeManagedLoop(from: "S", initiate: initiate, targetQueue: self.loopQueue)
            }

            describe("connecting") {
                describe("happy cases") {
                    it("should allow connecting before starting") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        expect(connectable.recorder.items).toEventually(equal(["S"]))
                    }

                    it("should allow connecting after starting") {
                        loop.start()
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                    }

                    it("should hook up the connectable's events to the loop") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        connectable.dispatch("hey")

                        expect(connectable.recorder.items).toEventually(equal(["S", "S-hey"]))
                    }

                    it("should hook up the connectable's events to the loop when connecting after starting") {
                        loop.start()
                        loop.connect(connectable, acceptQueue: self.connectableQueue)

                        connectable.dispatch("hey")

                        expect(connectable.recorder.items).toEventually(equal(["S", "S-hey"]))
                    }

                    it("should ignore events sent while loop is stopped") {
                        connectable.dispatch("hey")
                        self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                        expect(connectable.recorder.items).to(beEmpty())
                    }

                    it("should ignore events sent while connectable disposal is pending") {
                        loop.start()

                        self.connectableQueue.sync {
                            loop.stop()
                            connectable.dispatchSameQueue("late event")
                        }
                        self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                        expect(connectable.recorder.items).to(beEmpty())
                    }

                    context("given a connected and started loop") {
                        beforeEach {
                            loop.connect(connectable, acceptQueue: self.connectableQueue)
                            loop.start()

                            clearConnectableRecorder()
                        }

                        it("should allow stopping and starting again") {
                            loop.stop()
                            loop.start()
                        }

                        it("should send new models to the connectable") {
                            loop.stop()
                            loop.start()

                            connectable.dispatch("restarted")
                            self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                            expect(connectable.recorder.items).toEventually(equal(["S", "S-restarted"]))
                        }

                        it("should retain updated state") {
                            connectable.dispatch("hi")
                            self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                            loop.stop()

                            clearConnectableRecorder()

                            loop.start()

                            connectable.dispatch("restarted")

                            expect(connectable.recorder.items).toEventually(equal(["S-hi", "S-hi-restarted"]))
                        }

                        it("should indicate the running status") {
                            loop.stop()
                            expect(loop.isRunning).to(beFalse())

                            loop.start()
                            expect(loop.isRunning).to(beTrue())
                        }
                    }
                }

                describe("disposing connections") {
                    var modelObserver: MockConnectable!
                    var effectObserver: MockConnectable!
                    var loop: MobiusManagedLoop<String, String, String>!

                    beforeEach {
                        modelObserver = MockConnectable()
                        effectObserver = MockConnectable()
                        loop = Mobius
                            .loop(
                                update: Update { _, _ in .noChange },
                                effectHandler: effectObserver
                            )
                            .makeManagedLoop(from: "")
                        loop.connect(modelObserver, acceptQueue: .main)
                        loop.start()
                    }

                    it("Should dispose any listeners of the model") {
                        loop.stop()
                        expect(modelObserver.disposed).toEventually(beTrue())
                    }

                    it("Should dispose any effect handlers") {
                        loop.stop()
                        expect(effectObserver.disposed).to(beTrue())
                    }
                }
            }

            describe("disconnecting") {
                describe("happy cases") {
                    it("should allow disconnecting before starting") {
                        let connection = loop.connect(connectable, acceptQueue: self.connectableQueue)
                        connection.dispose()
                    }

                    it("should allow disconnecting after starting") {
                        let connection = loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()
                        connection.dispose()
                    }

                    it("should allow disconnecting after stopping") {
                        let connection = loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()
                        loop.stop()
                        connection.dispose()
                    }

                    it("should allow reconnecting after disconnecting") {
                        let connection = loop.connect(connectable, acceptQueue: self.connectableQueue)
                        connection.dispose()
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        expect(connectable.recorder.items).toEventually(equal(["S"]))
                    }

                    it("should not send events to a connectable disconnected before starting") {
                        let disconnectedConnectable = RecordingTestConnectable(expectedQueue: self.connectableQueue)
                        let connection = loop.connect(disconnectedConnectable, acceptQueue: self.connectableQueue)
                        connection.dispose()

                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        expect(connectable.recorder.items).toEventually(equal(["S"]))
                        expect(disconnectedConnectable.recorder.items).to(beEmpty())
                    }

                    it("should not send events to a connectable disconnected after starting") {
                        let disconnectedConnectable = RecordingTestConnectable(expectedQueue: self.connectableQueue)
                        let connection = loop.connect(disconnectedConnectable, acceptQueue: self.connectableQueue)

                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        connection.dispose()
                        connectable.dispatch("hey")

                        expect(connectable.recorder.items).toEventually(equal(["S", "S-hey"]))
                        expect(disconnectedConnectable.recorder.items).to(equal(["S"]))
                    }
                }
            }

            describe("starting and stopping") {
                describe("happy cases") {
                    it("should allow starting a stopping a connected loop") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()
                        loop.stop()
                    }

                    it("should allow starting a stopping without a connected connectable") {
                        loop.start()
                        loop.stop()
                    }

                    it("should allow dispatching an event from the event source immediately") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        eventSource.dispatchOnSubscribe("startup")
                        loop.start()
                        loop.stop()

                        expect(connectable.recorder.items).toEventually(equal(["S", "S-startup"]))
                    }

                    it("should execute the initiator on each start") {
                        activateInitiator = true
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()
                        loop.stop()
                        loop.start()
                        loop.stop()

                        // Note that there’s no "S" – the initiator takes effect before the model is ever published.
                        expect(connectable.recorder.items).toEventually(equal(["S-init", "S-init-init"]))
                        expect(effectHandler.recorder.items).toEventually(equal(["initEffect", "initEffect"]))
                    }
                }
                #if arch(x86_64) || arch(arm64)
                describe("error handling") {
                    it("should not allow starting a running loop") {
                        loop.start()
                        expect(loop.start()).to(raiseError())
                    }

                    it("should not allow stopping a stopped loop") {
                        expect(loop.stop()).to(raiseError())
                    }
                }
                #endif
            }

            describe("accessing the model") {
                describe("happy cases") {
                    it("should return the default model before starting") {
                        expect(loop.latestModel).to(equal("S"))
                    }

                    it("should read the model from a running loop") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        connectable.dispatch("an event")

                        expect(loop.latestModel).toEventually(equal("S-an event"))
                    }

                    it("should read the last loop model after stopping") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        connectable.dispatch("the last event")
                        self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                        expect(connectable.recorder.items).toEventually(equal(["S", "S-the last event"]))

                        loop.stop()

                        expect(loop.latestModel).to(equal("S-the last event"))
                    }

                    it("should start from the last loop model on restart") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()

                        connectable.dispatch("the last event")
                        self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                        loop.stop()

                        clearConnectableRecorder()

                        loop.start()

                        expect(connectable.recorder.items).toEventually(equal(["S-the last event"]))
                    }

                    it("should support replacing the model when stopped") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)

                        loop.replaceModel("R")

                        loop.start()

                        expect(connectable.recorder.items).toEventually(equal(["R"]))
                    }
                }

                #if arch(x86_64) || arch(arm64)
                describe("error handling") {
                    it("should not allow replacing the model when running") {
                        loop.connect(connectable, acceptQueue: self.connectableQueue)
                        loop.start()
                        expect(loop.replaceModel("nononono")).to(raiseError())
                    }
                }
                #endif
            }

            describe("dispatching events") {
                beforeEach {
                    loop.connect(connectable, acceptQueue: self.connectableQueue)
                }

                it("should be possible to dispatch events after start") {
                    loop.start()

                    loop.dispatchEvent("one")
                    loop.dispatchEvent("two")
                    loop.dispatchEvent("three")

                    expect(connectable.recorder.items).toEventually(equal(["S", "S-one", "S-one-two", "S-one-two-three"]))
                }

                it("should queue up events dispatched before start to support racy initializations") {
                    eventSource.dispatchOnSubscribe("event source event")
                    loop.start()

                    expect(connectable.recorder.items).toEventually(equal(["S", "S-event source event"]))
                }

                it("should dispatch events from the event source") {
                    loop.start()
                    eventSource.dispatch("event source event")

                    expect(connectable.recorder.items).toEventually(equal(["S", "S-event source event"]))
                }
            }

            describe("deallocating") {
                var modelObserver: MockConsumerConnectable!
                var loop: MobiusManagedLoop<NSObject, String, String>!
                var consumerWrapper: MockConsumerConnectable.ConsumerWrapper!
                var connection: Disposable!

                beforeEach {
                    consumerWrapper = MockConsumerConnectable.ConsumerWrapper()
                    modelObserver = MockConsumerConnectable(consumerWrapper: consumerWrapper)
                    loop = MobiusManagedLoop(
                        model: NSObject(),
                        update: Update { model, _ in .next(model) },
                        eventSource: AnyEventSource(eventSource),
                        effectHandler: AnyConnectable(effectHandler),
                        logger: AnyMobiusLogger(NoopLogger()),
                        targetQueue: self.loopQueue
                    )
                    connection = loop.connect(modelObserver)
                    loop.start()
                }

                it("should release any references to the loop") {
                    self.makeSureAllEffectsAndEventsHaveBeenProcessed()
                    loop.stop()
                    connection.dispose()
                    loop = nil
                    expect(modelObserver.model).to(beNil())
                }
            }
        }
    }

    func makeSureAllEffectsAndEventsHaveBeenProcessed() {
        loopQueue.sync {
            // Waiting synchronously for effects to be completed
        }

        connectableQueue.sync {
            // Waiting synchronously for connectable observations to be completed
        }
    }
}
