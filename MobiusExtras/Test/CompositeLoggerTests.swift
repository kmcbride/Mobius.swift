// Copyright (c) 2020-2021 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import MobiusCore
import MobiusExtras
import Nimble
import Quick

class CompositeLoggerTests: QuickSpec {
    override func spec() {
        describe("CompositeLogger") {
            var logMessages: [String]!
            var compositeLogger: AnyMobiusLogger<String, String, String>!

            beforeEach {
                logMessages = []
                compositeLogger = AnyMobiusLogger(
                    SimpleLogger(tag: "4", consumer: { logMessages.append($0) })
                        .append(SimpleLogger(tag: "5", consumer: { logMessages.append($0) }))
                        .append([SimpleLogger(tag: "6", consumer: { logMessages.append($0) })])
                        .append(
                            SimpleLogger(tag: "7", consumer: { logMessages.append($0) }),
                            SimpleLogger(tag: "8", consumer: { logMessages.append($0) })
                        )
                        .prepend(SimpleLogger(tag: "3", consumer: { logMessages.append($0) }))
                        .prepend([SimpleLogger(tag: "2", consumer: { logMessages.append($0) })])
                        .prepend(
                            SimpleLogger(tag: "0", consumer: { logMessages.append($0) }),
                            SimpleLogger(tag: "1", consumer: { logMessages.append($0) })
                        )
                )
            }

            it("should send willInitiate to each logger in order") {
                compositeLogger.willInitiate(model: "Initial")

                let expectedMessages: [String] = (0...8).reduce(into: []) { messages, index in
                    messages.append("\(index): Initializing loop")
                }
                expect(logMessages).to(equal(expectedMessages))
            }

            it("should send didInitiate to each logger in reverse order") {
                compositeLogger.didInitiate(
                    model: "Incoming",
                    first: First(model: "Outgoing", effects: ["Effect1", "Effect2"])
                )

                let expectedMessages: [String] = (0...8).reversed().reduce(into: []) { messages, index in
                    messages.append("\(index): Loop initialized, starting from model: Outgoing")
                    messages.append("\(index): Effect dispatched: Effect1")
                    messages.append("\(index): Effect dispatched: Effect2")
                }
                expect(logMessages).to(equal(expectedMessages))
            }

            it("should send willUpdate to each logger in order") {
                compositeLogger.willUpdate(model: "Incoming", event: "Event")

                let expectedMessages: [String] = (0...8).reduce(into: []) { messages, index in
                    messages.append("\(index): Event received: Event")
                }
                expect(logMessages).to(equal(expectedMessages))
            }

            it("should send didUpdate to each logger in reverse order") {
                compositeLogger.didUpdate(
                    model: "Incoming",
                    event: "Event",
                    next: .next("Outgoing", effects: ["Effect1", "Effect2"])
                )

                let expectedMessages: [String] = (0...8).reversed().reduce(into: []) { messages, index in
                    messages.append("\(index): Model updated: Outgoing")
                    messages.append("\(index): Effect dispatched: Effect1")
                    messages.append("\(index): Effect dispatched: Effect2")
                }
                expect(logMessages).to(equal(expectedMessages))
            }
        }
    }
}
