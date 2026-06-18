import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A reward returned by the referral APIs — a generic `amount` of `unit` plus
/// optional human copy ("Your 100 drops are ready").
///
/// `unit == "week"` is the conventional value mapped to trial time; any other
/// value is an app-defined currency/credit (e.g. "drop", "gem") you grant by
/// `amount`. Read `amount`/`unit` for custom currencies; `weeks` stays for
/// week-denominated programs and existing call sites.
public struct ReferralReward: Equatable, Sendable {
    /// Quantity granted, in `unit`.
    public let amount: Int
    /// Unit of the reward ("week" → trial time; otherwise a custom currency).
    public let unit: String
    /// Optional explicit plural of `unit` ("drops") for display copy.
    public let unitPlural: String?
    /// Optional human copy ("Your 100 drops are ready").
    public let label: String?

    /// Back-compat: free weeks to grant. Equals `amount` for week-denominated
    /// rewards and 0 for custom currencies (use `amount`/`unit` for those).
    public var weeks: Int { unit == "week" ? amount : 0 }

    public init(amount: Int, unit: String, unitPlural: String? = nil, label: String? = nil) {
        self.amount = amount
        self.unit = unit
        self.unitPlural = unitPlural
        self.label = label
    }
}

/// Result of attributing a referred install on first launch.
public struct ReferralAttribution: Equatable, Sendable {
    /// True the first time this install is attributed; false on a repeat call.
    public let alreadyAttributed: Bool
    /// The new user's reward, when the program rewards referees. Grant this.
    public let refereeReward: ReferralReward?
}

/// Result of a referrer claiming owed rewards.
public struct ReferralRewards: Equatable, Sendable {
    /// Total amount newly earned since the last check, in `unit` — grant this.
    public let amount: Int
    /// Unit of the reward ("week" or a custom currency).
    public let unit: String
    /// How many friends' installs those rewards represent.
    public let newReferrals: Int

    /// Back-compat: free weeks newly earned. Equals `amount` for week-
    /// denominated rewards and 0 for custom currencies.
    public var weeks: Int { unit == "week" ? amount : 0 }

    public init(amount: Int, unit: String, newReferrals: Int) {
        self.amount = amount
        self.unit = unit
        self.newReferrals = newReferrals
    }
}

extension ReferralReward {
    /// Map a decoded server reward payload, tolerating older backends that sent
    /// only `weeks` (→ amount with unit "week").
    init(_ payload: SessionClient.RewardPayload) {
        self.init(
            amount: payload.amount ?? payload.weeks ?? 0,
            unit: payload.unit ?? "week",
            unitPlural: payload.unitPlural,
            label: payload.label
        )
    }
}

extension RetentionFlow {
    /// Prefix the AppMate invite landing writes ahead of the referral claim
    /// token so the SDK recognizes one on the clipboard.
    private static let referralClaimPrefix = "amrf_"

    /// Fetch (minting on first call) the user's referral share link. Share
    /// this from your "Invite a friend" button. Returns `nil` if the referral
    /// program isn't published or the network call fails.
    ///
    /// IMPORTANT: do NOT grant the referrer's reward here — it's earned only
    /// when a friend installs. Use ``claimReferralRewards(userId:)`` on launch.
    public static func referralShareLink(userId: String) async -> URL? {
        guard let config = config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return nil
        }
        let client = SessionClient(config: config)
        guard let resp = try? await client.referralCode(userId: userId) else {
            return nil
        }
        return URL(string: resp.shareUrl)
    }

    /// The default share message configured for the program (so you can put it
    /// in the share sheet alongside the link). Returns `nil` on failure.
    public static func referralShareMessage(userId: String) async -> String? {
        guard let config = config else { return nil }
        let client = SessionClient(config: config)
        return try? await client.referralCode(userId: userId).shareMessage
    }

    /// The user's short, human-readable referral **code**, formatted for
    /// display (e.g. `"K7Q4-R9XP"`). Show it in a copyable "Your code" chip on
    /// your Invite screen so people can share the code directly, not just the
    /// link. A friend redeems it with ``redeemReferral(code:userId:anonymousId:)``.
    /// Returns `nil` if the program isn't published or the call fails.
    public static func referralShareCode(userId: String) async -> String? {
        guard let config = config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return nil
        }
        let client = SessionClient(config: config)
        guard let resp = try? await client.referralCode(userId: userId) else {
            return nil
        }
        // Prefer the server's formatted form; fall back to grouping locally so
        // this keeps working against older backends that only return `code`.
        return resp.displayCode ?? formatShareCode(resp.code)
    }

    /// Group an 8-char code as `XXXX-XXXX` for display; pass anything else
    /// through unchanged.
    private static func formatShareCode(_ code: String) -> String {
        code.count == 8 ? "\(code.prefix(4))-\(code.suffix(4))" : code
    }

    /// Claim any referral rewards the user has newly earned from friends who
    /// installed. Call on app launch (and after sign-up). Returns `.weeks == 0`
    /// when nothing is owed. The server marks rewards claimed atomically, so a
    /// given install is only ever returned once.
    public static func claimReferralRewards(userId: String) async -> ReferralRewards {
        guard let config = config else {
            return ReferralRewards(amount: 0, unit: "week", newReferrals: 0)
        }
        let client = SessionClient(config: config)
        guard let resp = try? await client.referralRewards(userId: userId) else {
            return ReferralRewards(amount: 0, unit: "week", newReferrals: 0)
        }
        // Prefer the generic amount/unit; fall back to the legacy weeks field
        // for older backends.
        return ReferralRewards(
            amount: resp.amountOwed ?? resp.weeksOwed ?? 0,
            unit: resp.reward?.unit ?? "week",
            newReferrals: resp.newReferrals
        )
    }

    /// Redeem a referral straight from an inbound deep-link URL — the installed-
    /// app fast path. When a friend taps an invite link and your app is already
    /// installed, the AppMate invite page opens your app with a URL shaped like
    /// `yourscheme://retention-flow/action?type=referral&code=…`. Pass that URL
    /// here and the SDK pulls the code and redeems it (no clipboard, no paste
    /// banner). Returns `nil` if the URL isn't an AppMate referral link, so it's
    /// safe to funnel every inbound URL through it.
    ///
    /// ```swift
    /// .onOpenURL { url in
    ///     Task {
    ///         if let attr = await RetentionFlow.redeemReferralFromURL(url, userId: user.id),
    ///            let reward = attr.refereeReward {
    ///             grantFreeWeeks(reward.weeks)
    ///         }
    ///     }
    /// }
    /// ```
    public static func redeemReferralFromURL(
        _ url: URL,
        userId: String? = nil,
        anonymousId: String? = nil
    ) async -> ReferralAttribution? {
        guard
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            comps.host == "retention-flow",
            comps.path == "/action",
            comps.queryItems?.first(where: { $0.name == "type" })?.value == "referral",
            let code = comps.queryItems?
                .first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else { return nil }
        return await redeemReferral(
            code: code,
            userId: userId,
            anonymousId: anonymousId
        )
    }

    /// Redeem a short, human-readable referral **code** the friend typed in (or
    /// pasted via a Paste button) — no clipboard read, so this shows **no** iOS
    /// paste banner. Binds the install to the referrer and returns the new
    /// user's reward to grant. Idempotent per referee; returns `nil` on an
    /// unknown code, a self-referral, or a network failure.
    ///
    /// Use this for an "Enter invite code" field. For the deferred clipboard
    /// handoff (no typing), use ``attributeReferral(userId:anonymousId:)``.
    public static func redeemReferral(
        code: String,
        userId: String? = nil,
        anonymousId: String? = nil
    ) async -> ReferralAttribution? {
        guard let config = config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return nil
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let client = SessionClient(config: config)
        guard let resp = try? await client.attributeReferral(
            code: trimmed,
            userId: userId,
            anonymousId: anonymousId
        ) else { return nil }

        let reward = resp.refereeReward.map { ReferralReward($0) }
        return ReferralAttribution(
            alreadyAttributed: resp.alreadyAttributed ?? false,
            refereeReward: reward
        )
    }

    #if canImport(UIKit)
    /// Attribute a referred install on first launch. Reads the referral claim
    /// token the invite landing left on the clipboard, binds the install to the
    /// referrer (the reward trigger for both sides), clears the token, and
    /// returns the new user's reward to grant. Returns `nil` for organic
    /// installs (no token) or on failure.
    ///
    /// > Note: reading the clipboard shows the standard iOS paste banner — call
    /// > this at a natural "setting things up" moment on first launch.
    @MainActor
    public static func attributeReferral(
        userId: String? = nil,
        anonymousId: String? = nil
    ) async -> ReferralAttribution? {
        guard let config = config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return nil
        }
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings,
              let text = pasteboard.string?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              text.hasPrefix(referralClaimPrefix)
        else { return nil }

        let client = SessionClient(config: config)
        guard let resp = try? await client.attributeReferral(
            claimToken: text,
            userId: userId,
            anonymousId: anonymousId
        ) else { return nil }

        // Clear our token so a later launch doesn't re-attempt it.
        if pasteboard.string == text { pasteboard.string = "" }

        let reward = resp.refereeReward.map { ReferralReward($0) }
        return ReferralAttribution(
            alreadyAttributed: resp.alreadyAttributed ?? false,
            refereeReward: reward
        )
    }
    #endif
}
