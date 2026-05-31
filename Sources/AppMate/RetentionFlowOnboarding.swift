import Foundation

/// One answer captured by an onboarding-funnel `question` step. Single-select
/// questions decode as ``single``; multi-select as ``multiple``.
public enum OnboardingAnswer: Equatable, Sendable {
    case single(String)
    case multiple([String])

    /// All selected option ids, regardless of single/multi.
    public var values: [String] {
        switch self {
        case .single(let v): return [v]
        case .multiple(let vs): return vs
        }
    }

    /// The first selected option id, if any.
    public var first: String? { values.first }
}

extension OnboardingAnswer: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .single(s)
        } else if let arr = try? container.decode([String].self) {
            self = .multiple(arr)
        } else {
            // Unknown shape — surface as an empty multi rather than throwing,
            // so one odd answer never blocks recovering the rest.
            self = .multiple([])
        }
    }
}

/// The result of an onboarding funnel the user completed on the web, recovered
/// on first launch via ``RetentionFlow/fetchOnboardingResult(userId:anonymousId:)``
/// or ``RetentionFlow/claimOnboarding(claimToken:userId:anonymousId:)``.
public struct OnboardingResult: Equatable, Sendable {
    /// Captured answers keyed by the funnel step id.
    public let answers: [String: OnboardingAnswer]

    /// The email the user entered, if the funnel had an email-capture step
    /// and the user provided one.
    public let email: String?

    /// `true` when this claim token had already been redeemed on a previous
    /// launch (e.g. the user reinstalled). The answers are still returned.
    public let alreadyClaimed: Bool

    public init(
        answers: [String: OnboardingAnswer],
        email: String?,
        alreadyClaimed: Bool
    ) {
        self.answers = answers
        self.email = email
        self.alreadyClaimed = alreadyClaimed
    }

    /// Convenience: the selected option id(s) for a step, or `[]` if absent.
    public func values(forStep stepId: String) -> [String] {
        answers[stepId]?.values ?? []
    }
}
