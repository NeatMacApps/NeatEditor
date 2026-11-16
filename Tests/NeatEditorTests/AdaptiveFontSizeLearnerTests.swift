import Foundation
import Testing

@testable import NeatEditor

/// Pure Foundation learner tests: cold start, formula, caps, reversal,
/// rounding/clamping, and decode sanitization.
struct AdaptiveFontSizeLearnerTests {
    private func expect(_ actual: Double, near expected: Double) -> Bool {
        abs(actual - expected) < 0.000_001
    }

    @Test("cold start carries the fixed prior estimate and evidence")
    func coldStart() {
        let learner = AdaptiveFontSizeLearner()

        #expect(learner.estimate == 13)
        #expect(learner.evidence == 4)
        #expect(learner.defaultFontSize == 13)
    }

    @Test("the first sample moves the estimate by one fifth of the gap")
    func firstSampleUsesPriorRate() {
        var learner = AdaptiveFontSizeLearner()
        learner.learn(sample: 23)

        #expect(expect(learner.estimate, near: 13 + (23 - 13) / 5.0))
        #expect(learner.evidence == 5)
    }

    @Test("repeated samples cap evidence at twelve and keep the one-twelfth rate")
    func evidenceCapsAtTwelve() {
        var learner = AdaptiveFontSizeLearner()
        let target: CGFloat = 30
        for _ in 0..<30 { learner.learn(sample: target) }

        #expect(learner.evidence == 12)

        let before = learner.estimate
        learner.learn(sample: target)
        let expected = before + (Double(target) - before) / 12.0
        #expect(expect(learner.estimate, near: expected))
        #expect(learner.evidence == 12)
    }

    @Test("a long run of small sizes reverses a previously large preference")
    func preferenceReverses() {
        var learner = AdaptiveFontSizeLearner()
        for _ in 0..<20 { learner.learn(sample: 30) }
        #expect(learner.estimate > 25)

        for _ in 0..<20 { learner.learn(sample: 10) }
        #expect(learner.estimate < 15)
    }

    @Test("default size rounds to the nearest whole point and clamps samples")
    func roundingAndClamping() {
        #expect(AdaptiveFontSizeLearner(estimate: 15.5, evidence: 8).defaultFontSize == 16)
        #expect(AdaptiveFontSizeLearner(estimate: 15.4, evidence: 8).defaultFontSize == 15)

        var learner = AdaptiveFontSizeLearner()
        learner.learn(sample: 1000)
        #expect(expect(learner.estimate, near: 13 + (36 - 13) / 5.0))

        learner.learn(sample: -1000)
        #expect(learner.estimate >= 10 && learner.estimate <= 36)
    }

    @Test("non-finite and out-of-range values are sanitized on init")
    func sanitizesOnInit() {
        #expect(AdaptiveFontSizeLearner(estimate: .nan).estimate == 13)
        #expect(AdaptiveFontSizeLearner(estimate: .infinity).estimate == 13)
        #expect(AdaptiveFontSizeLearner(estimate: 99).estimate == 36)
        #expect(AdaptiveFontSizeLearner(estimate: -5).estimate == 10)
        #expect(AdaptiveFontSizeLearner(evidence: 0).evidence == 4)
        #expect(AdaptiveFontSizeLearner(evidence: 99).evidence == 12)
    }

    @Test("decode fills missing fields and repairs invalid values")
    func decodeRepairs() throws {
        let empty = try JSONDecoder().decode(
            AdaptiveFontSizeLearner.self,
            from: Data(#"{}"#.utf8)
        )
        #expect(empty.estimate == 13)
        #expect(empty.evidence == 4)

        let corrupt = try JSONDecoder().decode(
            AdaptiveFontSizeLearner.self,
            from: Data(#"{"estimate": 99, "evidence": -3}"#.utf8)
        )
        #expect(corrupt.estimate == 36)
        #expect(corrupt.evidence == 4)

        let roundTripped = try JSONDecoder().decode(
            AdaptiveFontSizeLearner.self,
            from: JSONEncoder().encode(AdaptiveFontSizeLearner(estimate: 15.5, evidence: 7))
        )
        #expect(expect(roundTripped.estimate, near: 15.5))
        #expect(roundTripped.evidence == 7)
    }

    @Test("a non-finite persisted estimate is reset to the cold start")
    func decodeResetsNonFiniteEstimate() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let learner = try decoder.decode(
            AdaptiveFontSizeLearner.self,
            from: Data(#"{"estimate": "NaN", "evidence": 12}"#.utf8)
        )
        #expect(learner.estimate == 13)
        #expect(learner.evidence == 12)
    }
}
