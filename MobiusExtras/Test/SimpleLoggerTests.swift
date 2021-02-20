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

class SimpleLoggerTests: QuickSpec {
    override func spec() {
        describe("SimpleLogger") {
            var logMessages: [String]!
            var logger: SimpleLogger<String, String, String>!

            beforeEach {
                logMessages = []
                logger = SimpleLogger(tag: "Simple") { logMessages.append($0) }
            }

            it("should log tagged willInitiate") {
                logger.willInitiate(model: "Initial")

                let expectedMessages = ["Simple: Initializing loop"]
                expect(logMessages).to(equal(expectedMessages))
            }

            it("should log tagged didInitiate") {
                logger.didInitiate(
                    model: "Incoming",
                    first: First(model: "Outgoing", effects: ["Effect1", "Effect2"])
                )

                let expectedMessages = [
                    "Simple: Loop initialized, starting from model: Outgoing",
                    "Simple: Effect dispatched: Effect1",
                    "Simple: Effect dispatched: Effect2",
                ]
                expect(logMessages).to(equal(expectedMessages))
            }

            it("should log tagged willUpdate") {
                logger.willUpdate(model: "Incoming", event: "Event")

                let expectedMessages = ["Simple: Event received: Event"]
                expect(logMessages).to(equal(expectedMessages))
            }

            it("should log tagged didUpdate") {
                logger.didUpdate(
                    model: "Incoming",
                    event: "Event",
                    next: .next("Outgoing", effects: ["Effect1", "Effect2"])
                )

                let expectedMessages = [
                    "Simple: Model updated: Outgoing",
                    "Simple: Effect dispatched: Effect1",
                    "Simple: Effect dispatched: Effect2",
                ]
                expect(logMessages).to(equal(expectedMessages))
            }
        }
    }
}
