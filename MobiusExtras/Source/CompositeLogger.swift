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

import Foundation
import MobiusCore

public extension MobiusLogger {
    /// Appends the given logger to this logger.
    ///
    /// - Parameter logger: The logger to append.
    /// - Returns: A logger that calls one logger before another.
    func append<Logger: MobiusLogger>(_ logger: Logger) -> CompositeLogger<Self, Logger>
        where Self.Model == Logger.Model, Self.Event == Logger.Event, Self.Effect == Logger.Effect
    {
        return .init(prefix: self, suffix: logger)
    }

    /// Prepends the given logger to this logger.
    ///
    /// - Parameter logger: The logger to prepend.
    /// - Returns: A logger that calls one logger before another.
    func prepend<Logger: MobiusLogger>(_ logger: Logger) -> CompositeLogger<Logger, Self>
        where Self.Model == Logger.Model, Self.Event == Logger.Event, Self.Effect == Logger.Effect
    {
        return .init(prefix: logger, suffix: self)
    }
}

/// A logger that calls one logger before calling another.
public struct CompositeLogger<Prefix: MobiusLogger, Suffix: MobiusLogger>: MobiusLogger
    where Prefix.Model == Suffix.Model, Prefix.Event == Suffix.Event, Prefix.Effect == Suffix.Effect
{
    public typealias Model = Suffix.Model
    public typealias Event = Suffix.Event
    public typealias Effect = Suffix.Effect

    public let prefix: Prefix
    public let suffix: Suffix

    public init(prefix: Prefix, suffix: Suffix) {
        self.prefix = prefix
        self.suffix = suffix
    }

    public func willInitiate(model: Model) {
        prefix.willInitiate(model: model)
        suffix.willInitiate(model: model)
    }

    public func didInitiate(model: Model, first: First<Model, Effect>) {
        suffix.didInitiate(model: model, first: first)
        prefix.didInitiate(model: model, first: first)
    }

    public func willUpdate(model: Model, event: Event) {
        prefix.willUpdate(model: model, event: event)
        suffix.willUpdate(model: model, event: event)
    }

    public func didUpdate(model: Model, event: Event, next: Next<Model, Effect>) {
        suffix.didUpdate(model: model, event: event, next: next)
        prefix.didUpdate(model: model, event: event, next: next)
    }
}

public extension MobiusLogger {
    /// Appends the given loggers to this logger.
    ///
    /// - Parameter loggers: The loggers to append.
    /// - Returns: A logger that calls multiple loggers sequentially.
    func append<Logger: MobiusLogger>(_ loggers: Logger...) -> CompositeLogger<Self, SequentialLogger<[Logger]>>
        where Self.Model == Logger.Model, Self.Event == Logger.Event, Self.Effect == Logger.Effect
    {
        return .init(prefix: self, suffix: SequentialLogger(loggers: loggers))
    }

    /// Appends the given loggers to this logger.
    ///
    /// - Parameter loggers: The sequence of loggers to append.
    /// - Returns: A logger that calls multiple loggers sequentially.
    func append<Loggers: Sequence>(_ loggers: Loggers) -> CompositeLogger<Self, SequentialLogger<Loggers>>
        where Self.Model == Loggers.Element.Model, Self.Event == Loggers.Element.Event,
              Self.Effect == Loggers.Element.Effect
    {
        return .init(prefix: self, suffix: SequentialLogger(loggers: loggers))
    }

    /// Prepends the given loggers to this logger.
    ///
    /// - Parameter loggers: The loggers to prepend.
    /// - Returns: A logger that calls multiple loggers sequentially.
    func prepend<Logger: MobiusLogger>(_ loggers: Logger...) -> CompositeLogger<SequentialLogger<[Logger]>, Self>
        where Self.Model == Logger.Model, Self.Event == Logger.Event, Self.Effect == Logger.Effect
    {
        return .init(prefix: SequentialLogger(loggers: loggers), suffix: self)
    }

    /// Prepends the given loggers to this logger.
    ///
    /// - Parameter loggers: The sequence of loggers to prepend.
    /// - Returns: A logger that calls multiple loggers sequentially.
    func prepend<Loggers: Sequence>(_ loggers: Loggers) -> CompositeLogger<SequentialLogger<Loggers>, Self>
        where Self.Model == Loggers.Element.Model, Self.Event == Loggers.Element.Event,
              Self.Effect == Loggers.Element.Effect
    {
        return .init(prefix: SequentialLogger(loggers: loggers), suffix: self)
    }
}

/// A logger that calls multiple loggers sequentially.
public struct SequentialLogger<Loggers: Sequence>: MobiusLogger
    where Loggers.Element: MobiusLogger
{
    public typealias Model = Loggers.Element.Model
    public typealias Event = Loggers.Element.Event
    public typealias Effect = Loggers.Element.Effect

    public let loggers: Loggers

    public init(loggers: Loggers) {
        self.loggers = loggers
    }

    public func willInitiate(model: Model) {
        loggers.forEach { $0.willInitiate(model: model) }
    }

    public func didInitiate(model: Model, first: First<Model, Effect>) {
        loggers.reversed().forEach { $0.didInitiate(model: model, first: first) }
    }

    public func willUpdate(model: Model, event: Event) {
        loggers.forEach { $0.willUpdate(model: model, event: event) }
    }

    public func didUpdate(model: Model, event: Event, next: Next<Model, Effect>) {
        loggers.reversed().forEach { $0.didUpdate(model: model, event: event, next: next) }
    }
}
