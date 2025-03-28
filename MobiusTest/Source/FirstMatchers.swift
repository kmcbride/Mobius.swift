// Copyright Spotify AB.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import MobiusCore
import XCTest

public typealias FirstPredicate<Model, Effect> = Predicate<First<Model, Effect>>

/// Function to produce an `AssertFirst` function to be used with the `InitSpec`
///
/// - Parameter predicates: Nimble `Predicate` that verifies a first. Can be produced through `FirstMatchers`
/// - Returns: An `AssertFirst` function to be used with the `InitSpec`
public func assertThatFirst<Model, Effect>(
    _ predicates: FirstPredicate<Model, Effect>...,
    failFunction: @escaping AssertionFailure = XCTFail
) -> AssertFirst<Model, Effect> {
    return { (result: First<Model, Effect>) in
        predicates.forEach({ predicate in
            let predicateResult = predicate(result)
            if case .failure(let message, let file, let line) = predicateResult {
                failFunction(message, file, line)
            }
        })
    }
}

/// Returns a `Predicate` that matches `First` instances with a M that is equal to the supplied one.
///
/// - Parameter expected: the expected M
/// - Returns: a `Predicate` determening if a `First` contains the expected M
public func hasModel<Model: Equatable, Effect>(
    _ expected: Model,
    file: StaticString = #file,
    line: UInt = #line
) -> FirstPredicate<Model, Effect> {
    return { (first: First<Model, Effect>) in
        if first.model != expected {
            return .failure(
                message: "Different model than expected (−), got (+): \n" +
                    "\(dumpDiff(expected, first.model))",
                file: file,
                line: line
            )
        }
        return .success
    }
}

/// Returns a `Predicate` that matches `First` instances with no Es.
///
/// - Returns: a `Predicate` determening if a `First` contains no Es
public func hasNoEffects<Model, Effect>(
    file: StaticString = #file,
    line: UInt = #line
) -> FirstPredicate<Model, Effect> {
    return { (first: First<Model, Effect>) in
        if !first.effects.isEmpty {
            return .failure(
                message: "Expected no effects, got <\(first.effects)>",
                file: file,
                line: line
            )
        }
        return .success
    }
}

/// Returns a `Predicate` that matches if all the supplied Es are present in the supplied `First` in any order.
/// The `First` may have more Es than the ones included.
///
/// - Parameter Es: the Es to match (possibly empty)
/// - Returns: a `Predicate` that matches `First` instances that include all the supplied Es
public func hasEffects<Model, Effect: Equatable>(
    _ expected: [Effect],
    file: StaticString = #file,
    line: UInt = #line
) -> FirstPredicate<Model, Effect> {
    return { (first: First<Model, Effect>) in
        let actual = first.effects
        let unmatchedExpected = expected.filter { !actual.contains($0) }
        guard !unmatchedExpected.isEmpty else { return .success }

        // Find the effects that were produced but not expected - this is permitted, but there might be a close match
        // there
        let unmatchedActual = actual.filter { !expected.contains($0) }

        return .failure(
            message: "Missing \(countedEffects(unmatchedExpected, label: "expected")) (−), got (+)" +
                " (with \(countedEffects(unmatchedActual, label: "actual")) unmatched):\n" +
                dumpDiffFuzzy(expected: unmatchedExpected, actual: unmatchedActual, withUnmatchedActual: false),
            file: file,
            line: line
        )
    }
}

/// Constructs a matcher that matches if only the supplied effects are present in the supplied `First`, in any order.
///
/// - Parameter expected: the effects to match (possibly empty)
/// - Returns: a `Predicate` that matches `First` instances that include all the supplied effects
public func hasOnlyEffects<Model, Effect: Equatable>(
    _ expected: [Effect],
    file: StaticString = #file,
    line: UInt = #line
) -> FirstPredicate<Model, Effect> {
    return { (first: First<Model, Effect>) in
        let actual = first.effects
        let unmatchedExpected = expected.filter { !actual.contains($0) }
        let unmatchedActual = actual.filter { !expected.contains($0) }

        var errorString = [
            !unmatchedExpected.isEmpty ? "missing \(countedEffects(unmatchedExpected, label: "expected")) (−)" : nil,
            !unmatchedActual.isEmpty ? "got \(countedEffects(unmatchedActual, label: "actual unmatched")) (+)" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        errorString = errorString.prefix(1).capitalized + errorString.dropFirst()

        if !errorString.isEmpty {
            return .failure(
                message: "\(errorString):\n" +
                    dumpDiffFuzzy(expected: unmatchedExpected, actual: unmatchedActual, withUnmatchedActual: true),
                file: file,
                line: line
            )
        }

        return .success
    }
}

/// Constructs a matcher that matches if the supplied effects are equal to the supplied `First`.
///
/// - Parameter expected: the effects to match (possibly empty)
/// - Returns: a `Predicate` that matches `First` instances that include all the supplied effects
public func hasExactlyEffects<Model, Effect: Equatable>(
    _ expected: [Effect],
    file: StaticString = #file,
    line: UInt = #line
) -> FirstPredicate<Model, Effect> {
    return { (first: First<Model, Effect>) in
        if first.effects != expected {
            return .failure(
                message: "Different effects than expected (−), got (+): \n" +
                    "\(dumpDiff(expected, first.effects))",
                file: file,
                line: line
            )
        }
        return .success
    }
}

private func countedEffects<T>(_ effects: [T], label: String) -> String {
    let count = effects.count
    return count == 1 ? "1 \(label) effect" : "\(count) \(label) effects"
}
