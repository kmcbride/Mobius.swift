// Copyright Spotify AB.
// SPDX-License-Identifier: Apache-2.0

@testable import MobiusCore

import Foundation
import Nimble
import Quick

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
class MobiusControllerTests: QuickSpec {
    let loopQueue = DispatchQueue(label: "loop queue")
    let viewQueue = DispatchQueue(label: "view queue")

    // swiftlint:disable:next function_body_length
    override func spec() {
        describe("MobiusController") {
            var controller: MobiusController<String, String, String>!
            var updateFunction: Update<String, String, String>!
            var initiate: Initiate<String, String>!
            var view: RecordingTestConnectable!
            var eventSource: TestEventSource<String>!
            var connectableEventSource: TestConnectableEventSource<String, String>!
            var effectHandler: RecordingTestConnectable!
            var activateInitiator: Bool!

            func clearViewRecorder() {
                makeSureAllEffectsAndEventsHaveBeenProcessed()
                view.recorder.clear()
            }

            beforeEach {
                view = RecordingTestConnectable(expectedQueue: self.viewQueue)
                let loopQueue = self.loopQueue

                updateFunction = .init { model, event in
                    dispatchPrecondition(condition: .onQueue(loopQueue))
                    return .next("\(model)-\(event)")
                }

                activateInitiator = false
                initiate = .init { model in
                    if activateInitiator {
                        return First(model: "\(model)-init", effects: ["initEffect"])
                    } else {
                        return First(model: model)
                    }
                }

                eventSource = TestEventSource()

                effectHandler = RecordingTestConnectable()

                controller = Mobius.loop(update: updateFunction, effectHandler: effectHandler)
                    .withEventSource(eventSource)
                    .makeController(
                        from: "S",
                        initiate: initiate,
                        loopQueue: self.loopQueue,
                        viewQueue: self.viewQueue
                    )
            }

            describe("connecting") {
                describe("happy cases") {
                    it("should allow connecting before starting") {
                        controller.connectView(view)
                        controller.start()

                        expect(view.recorder.items).toEventually(equal(["S"]))
                    }
                    it("should hook up the view's events to the loop") {
                        controller.connectView(view)
                        controller.start()

                        view.dispatch("hey")

                        expect(view.recorder.items).toEventually(equal(["S", "S-hey"]))
                    }
                    it("should allow multiple connections") {
                        let secondaryView = RecordingTestConnectable(expectedQueue: self.viewQueue)

                        controller.connectView(view)
                        controller.connectView(secondaryView)
                        controller.start()

                        expect(view.recorder.items).toEventually(equal(["S"]))
                        expect(secondaryView.recorder.items).toEventually(equal(["S"]))
                    }

                    context("given a connected and started loop") {
                        beforeEach {
                            controller.connectView(view)
                            controller.start()

                            clearViewRecorder()
                        }
                        it("should allow stopping and starting again") {
                            controller.stop()
                            controller.start()
                        }
                        it("should send new models to the view") {
                            controller.stop()
                            controller.start()

                            view.dispatch("restarted")
                            self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                            expect(view.recorder.items).toEventually(equal(["S", "S-restarted"]))
                        }
                        it("should retain updated state") {
                            view.dispatch("hi")
                            self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                            controller.stop()

                            clearViewRecorder()

                            controller.start()

                            view.dispatch("restarted")

                            expect(view.recorder.items).toEventually(equal(["S-hi", "S-hi-restarted"]))
                        }
                        it("should indicate the running status") {
                            controller.stop()
                            expect(controller.running).to(beFalse())

                            controller.start()
                            expect(controller.running).to(beTrue())
                        }
                    }
                }

                describe("disposing connections") {
                    var modelObserver: MockConnectable!
                    var effectObserver: MockConnectable!
                    var controller: MobiusController<String, String, String>!

                    beforeEach {
                        modelObserver = MockConnectable()
                        effectObserver = MockConnectable()
                        controller = Mobius.loop(update: Update { _, _ in .noChange }, effectHandler: effectObserver)
                            .makeController(from: "")
                        controller.connectView(modelObserver)
                        controller.start()
                    }

                    it("should dispose any listeners of the model") {
                        controller.stop()
                        expect(modelObserver.disposed).toEventually(beTrue())
                    }

                    it("should dispose any effect handlers") {
                        controller.stop()
                        expect(effectObserver.disposed).to(beTrue())
                    }
                }

                describe("error handling") {
                    it("should not allow connecting after starting") {
                        controller.connectView(view)
                        controller.start()

                        expect(controller.connectView(view)).to(raiseError())
                    }
                }
            }

            describe("disconnecting") {
                describe("happy cases") {
                    it("should allow disconnecting before starting") {
                        controller.connectView(view)
                        controller.disconnectView()
                    }
                    it("should allow disconnecting after stopping") {
                        controller.connectView(view)
                        controller.start()
                        controller.stop()
                        controller.disconnectView()
                    }
                    it("should allow reconnecting after disconnecting") {
                        controller.connectView(view)
                        controller.disconnectView()
                        controller.connectView(view)
                        controller.start()

                        expect(view.recorder.items).toEventually(equal(["S"]))
                    }
                    it("should allow disconnecting by id") {
                        let secondaryView = RecordingTestConnectable(expectedQueue: self.viewQueue)

                        let connectionID = controller.connectView(view)
                        let secondaryConnectionID = controller.connectView(secondaryView)

                        controller.disconnectView(id: connectionID)
                        controller.disconnectView(id: secondaryConnectionID)
                    }
                    it("should not send events to a disconnected view") {
                        let disconnectedView = RecordingTestConnectable(expectedQueue: self.viewQueue)
                        controller.connectView(disconnectedView)
                        controller.disconnectView()

                        controller.connectView(view)
                        controller.start()

                        expect(view.recorder.items).toEventually(equal(["S"]))
                        expect(disconnectedView.recorder.items).to(beEmpty())
                    }
                    it("should not allow disconnecting before stopping") {
                        controller.connectView(view)
                        controller.start()

                        expect(controller.disconnectView()).to(raiseError())
                    }
                }

                #if arch(x86_64) || arch(arm64)
                describe("error handling") {
                    it("should not allow disconnecting while running") {
                        controller.start()
                        expect(controller.disconnectView()).to(raiseError())
                    }
                    it("should not allow disconnecting without a connection") {
                        controller.connectView(view)
                        controller.disconnectView()
                        expect(controller.disconnectView()).to(raiseError())
                    }

                    describe("multiple view connections") {
                        it("should not allow disconnecting without a connection id") {
                            let secondaryView = RecordingTestConnectable(expectedQueue: self.viewQueue)

                            controller.connectView(view)
                            controller.connectView(secondaryView)

                            expect(controller.disconnectView()).to(raiseError())
                        }
                        it("should not allow disconnecting an invalid connection id") {
                            let secondaryView = RecordingTestConnectable(expectedQueue: self.viewQueue)

                            controller.connectView(view)
                            controller.connectView(secondaryView)

                            expect(controller.disconnectView(id: UUID())).to(raiseError())
                        }
                    }
                }
                #endif
            }
            describe("starting and stopping") {
                describe("happy cases") {
                    it("should allow starting a stopping a connected controller") {
                        controller.connectView(view)
                        controller.start()
                        controller.stop()
                    }
                    it("should allow starting a stopping without a connected view") {
                        controller.start()
                        controller.stop()
                    }
                    it("should allow dispatching an event from the event source immediately") {
                        controller.connectView(view)
                        eventSource.dispatchOnSubscribe("startup")
                        controller.start()

                        // wait for event to be processed
                        expect(view.recorder.items).toEventually(equal(["S", "S-startup"]))

                        controller.stop()
                    }
                    it("should execute the initiator on each start") {
                        activateInitiator = true
                        controller.connectView(view)
                        controller.start()

                        // wait for event to be processed
                        expect(view.recorder.items).toEventually(equal(["S-init"]))
                        expect(effectHandler.recorder.items).toEventually(equal(["initEffect"]))

                        controller.stop()
                        controller.start()

                        // wait for event to be processed
                        expect(view.recorder.items).toEventually(equal(["S-init", "S-init-init"]))
                        expect(effectHandler.recorder.items).toEventually(equal(["initEffect", "initEffect"]))

                        controller.stop()
                    }
                }
                #if arch(x86_64) || arch(arm64)
                describe("error handling") {
                    it("should not allow starting a running controller") {
                        controller.connectView(view)
                        controller.start()
                        expect(controller.start()).to(raiseError())
                    }
                    it("should not allow stopping a loop before connecting") {
                        expect(controller.stop()).to(raiseError())
                    }
                    it("should not allow stopping a stopped controller") {
                        controller.connectView(view)
                        controller.start()
                        controller.stop()
                        expect(controller.stop()).to(raiseError())
                    }
                }
                #endif
            }
            describe("accessing the model") {
                describe("happy cases") {
                    it("should return the default model before starting") {
                        expect(controller.model).to(equal("S"))
                    }
                    it("should read the model from a running loop") {
                        controller.connectView(view)
                        controller.start()

                        view.dispatch("an event")

                        expect(controller.model).toEventually(equal("S-an event"))
                    }
                    it("should read the last loop model after stopping") {
                        controller.connectView(view)
                        controller.start()

                        view.dispatch("the last event")

                        // wait for event to be processed
                        expect(view.recorder.items).toEventually(equal(["S", "S-the last event"]))

                        controller.stop()

                        expect(controller.model).to(equal("S-the last event"))
                    }
                    it("should start from the last loop model on restart") {
                        controller.connectView(view)
                        controller.start()

                        view.dispatch("the last event")
                        self.makeSureAllEffectsAndEventsHaveBeenProcessed()

                        controller.stop()

                        clearViewRecorder()

                        controller.start()

                        expect(view.recorder.items).toEventually(equal(["S-the last event"]))
                    }
                    it("should support replacing the model when stopped") {
                        controller.connectView(view)

                        controller.replaceModel("R")

                        controller.start()

                        expect(view.recorder.items).toEventually(equal(["R"]))
                    }
                }
                #if arch(x86_64) || arch(arm64)
                describe("error handling") {
                    it("should not allow replacing the model when running") {
                        controller.connectView(view)
                        controller.start()
                        expect(controller.replaceModel("nononono")).to(raiseError())
                    }
                }
                #endif
            }

            describe("dispatching events") {
                beforeEach {
                    controller.connectView(view)
                    controller.start()
                }

                it("should dispatch events from the event source") {
                    eventSource.dispatch("event source event")

                    expect(view.recorder.items).toEventually(equal(["S", "S-event source event"]))
                }
            }

            describe("dispatching events using a connectable") {
                beforeEach {
                    // Rebuild the controller but use the Connectable instead of plain EventSource
                    connectableEventSource = .init()

                    controller = Mobius.loop(update: updateFunction, effectHandler: effectHandler)
                        .withEventSource(connectableEventSource)
                        .makeController(
                            from: "S",
                            initiate: initiate,
                            loopQueue: self.loopQueue,
                            viewQueue: self.viewQueue
                        )
                    controller.connectView(view)
                    controller.start()
                }

                it("should dispatch events from the event source") {
                    connectableEventSource.dispatch("event source event")

                    expect(view.recorder.items).toEventually(equal(["S", "S-event source event"]))
                }

                it("should receive models from the event source") {
                    view.dispatch("new model")
                    expect(connectableEventSource.models).toEventually(equal(["S", "S-new model"]))
                }

                it("should allow the event source to change with model updates") {
                    connectableEventSource.shouldProcessModel = { model in
                        model != "S-ignore"
                    }

                    view.dispatch("ignore")
                    view.dispatch("new model 2")
                    expect(connectableEventSource.models).toEventually(equal(["S", "S-ignore-new model 2"]))
                }

                it("should replace the event source") {
                    connectableEventSource = .init()

                    controller = Mobius.loop(update: updateFunction, effectHandler: effectHandler)
                        .withEventSource(eventSource)
                        .withEventSource(connectableEventSource)
                        .makeController(
                            from: "S",
                            initiate: initiate,
                            loopQueue: self.loopQueue,
                            viewQueue: self.viewQueue
                        )
                    controller.connectView(view)
                    controller.start()

                    eventSource.dispatch("event source event")
                    connectableEventSource.dispatch("connectable event source event")

                    // The connectable event source should have replaced the original normal event source
                    expect(connectableEventSource.models).toEventually(equal(["S", "S-connectable event source event"]))
                }
            }

            describe("deallocating") {
                var modelObserver: MockConsumerConnectable!
                var effectObserver: MockConnectable!
                var controller: MobiusController<NSObject, String, String>!
                var consumerWrapper: MockConsumerConnectable.ConsumerWrapper!

                beforeEach {
                    consumerWrapper = MockConsumerConnectable.ConsumerWrapper()
                    modelObserver = MockConsumerConnectable(consumerWrapper: consumerWrapper)
                    effectObserver = MockConnectable()
                    controller = Mobius
                        .loop(update: Update { model, _ in .next(model) }, effectHandler: effectObserver)
                        .makeController(from: NSObject(), loopQueue: self.loopQueue, viewQueue: self.viewQueue)
                    controller.connectView(modelObserver)
                    controller.start()
                }

                it("should release any references to the loop") {
                    self.makeSureAllEffectsAndEventsHaveBeenProcessed()
                    controller.stop()
                    controller.disconnectView()
                    controller = nil
                    expect(modelObserver.model).to(beNil())
                }
            }
        }
    }

    func makeSureAllEffectsAndEventsHaveBeenProcessed() {
        loopQueue.sync {
            // Waiting synchronously for effects to be completed
        }

        viewQueue.sync {
            // Waiting synchronously for view observations to be completed
        }
    }
}

class MockConnectable: Connectable {
    var disposed = false

    func connect(_ consumer: @escaping (String) -> Void) -> Connection<String> {
        return Connection(acceptClosure: { _ in }, disposeClosure: { self.disposed = true })
    }
}

class MockConsumerConnectable: Connectable {
    class ConsumerWrapper {
        var consumer: ((String) -> Void)?
    }

    // reference to the loop.model without retaining it
    // used to determine whether the loop is still alive
    private(set) weak var model: NSObject?

    // instance to retain the consumer passed to the connectable
    private let consumerWrapper: ConsumerWrapper

    init(consumerWrapper: ConsumerWrapper) {
        self.consumerWrapper = consumerWrapper
    }

    func connect(_ consumer: @escaping (String) -> Void) -> Connection<NSObject> {
        consumerWrapper.consumer = consumer
        return Connection(acceptClosure: { self.model = $0 }, disposeClosure: {})
    }
}
