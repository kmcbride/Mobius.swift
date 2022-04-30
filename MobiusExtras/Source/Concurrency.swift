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

public extension _PartialEffectRouter {
    func to<Success, Failure>(
        _ taskClosure: @escaping (EffectParameters, EffectCallback<Event>) -> Task<Success, Failure>
    ) -> EffectRouter<Effect, Event> {
        return to { parameters, callback in
            let task = taskClosure(parameters, callback)

            return AnonymousDisposable {
                task.cancel()
            }
        }
    }

    func to(
        _ asyncEvent: @escaping (EffectParameters) async -> Event
    ) -> EffectRouter<Effect, Event> {
        return to { parameters, callback in
            Task {
                let event = await asyncEvent(parameters)
                guard !Task.isCancelled else { return }
                callback.end(with: event)
            }
        }
    }

    func to(
        _ asyncEvents: @escaping (EffectParameters) async -> [Event]
    ) -> EffectRouter<Effect, Event> {
        return to { parameters, callback in
            Task {
                let events = await asyncEvents(parameters)
                guard !Task.isCancelled else { return }
                callback.end(with: events)
            }
        }
    }

    func to(
        _ asyncStream: @escaping (EffectParameters) -> AsyncStream<Event>
    ) -> EffectRouter<Effect, Event> {
        return to { parameters, callback in
            Task {
                for await event in asyncStream(parameters) {
                    guard !Task.isCancelled else { return }
                    callback.send(event)
                }
                callback.end()
            }
        }
    }
}

#endif
