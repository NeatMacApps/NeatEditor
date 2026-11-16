import Foundation

/// Bounded online learner that turns explicit font-size adjustments into a
/// default size for new documents. It is a pure value type with no timestamps,
/// history, content or paths: only the running estimate and evidence weight are
/// persisted.
///
/// The fixed prior (`evidence = 4`) makes an occasional adjustment move the
/// estimate slowly, while the cap keeps recent preferences weighted by an
/// exponentially-decaying average instead of a flat mean.
struct AdaptiveFontSizeLearner: Codable, Equatable, Sendable {
    static let minimumSize: Double = 10
    static let maximumSize: Double = 36
    static let coldStartEstimate: Double = 13
    static let coldStartEvidence = 4
    static let maximumEvidence = 12

    private(set) var estimate: Double
    private(set) var evidence: Int

    static let coldStart = AdaptiveFontSizeLearner()

    private enum CodingKeys: String, CodingKey {
        case estimate
        case evidence
    }

    init(
        estimate: Double = Self.coldStartEstimate,
        evidence: Int = Self.coldStartEvidence
    ) {
        self.estimate = Self.sanitizedEstimate(estimate)
        self.evidence = Self.sanitizedEvidence(evidence)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.coldStart
        estimate = Self.sanitizedEstimate(
            try container.decodeIfPresent(Double.self, forKey: .estimate) ?? defaults.estimate
        )
        evidence = Self.sanitizedEvidence(
            try container.decodeIfPresent(Int.self, forKey: .evidence) ?? defaults.evidence
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(estimate, forKey: .estimate)
        try container.encode(evidence, forKey: .evidence)
    }

    /// New-document default: the running estimate rounded to the nearest whole
    /// point and clamped to the supported size range.
    var defaultFontSize: CGFloat {
        let rounded = estimate.rounded()
        let clamped = rounded.clamped(to: Self.minimumSize...Self.maximumSize)
        return CGFloat(clamped)
    }

    /// Folds one explicit sample into the running estimate. The sample is
    /// clamped to the supported range first; the learning rate shrinks as
    /// evidence accumulates and stops shrinking at the fixed cap.
    mutating func learn(sample: CGFloat) {
        let clampedSample = Double(sample).clamped(to: Self.minimumSize...Self.maximumSize)
        let rate = 1.0 / Double(min(evidence + 1, Self.maximumEvidence))
        estimate += rate * (clampedSample - estimate)
        evidence = min(evidence + 1, Self.maximumEvidence)
    }

    private static func sanitizedEstimate(_ estimate: Double) -> Double {
        guard estimate.isFinite else {
            return coldStartEstimate
        }
        return estimate.clamped(to: minimumSize...maximumSize)
    }

    private static func sanitizedEvidence(_ evidence: Int) -> Int {
        evidence.clamped(to: coldStartEvidence...maximumEvidence)
    }
}
