import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A reward returned by the referral APIs — a number of free weeks plus
/// optional human copy ("Your free week is ready").
public struct ReferralReward: Equatable, Sendable {
    public let weeks: Int
    public let label: String?
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
    /// Free weeks newly earned since the last check — grant this many.
    public let weeks: Int
    /// How many friends' installs those weeks represent.
    public let newReferrals: Int
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

    /// Claim any referral rewards the user has newly earned from friends who
    /// installed. Call on app launch (and after sign-up). Returns `.weeks == 0`
    /// when nothing is owed. The server marks rewards claimed atomically, so a
    /// given install is only ever returned once.
    public static func claimReferralRewards(userId: String) async -> ReferralRewards {
        guard let config = config else {
            return ReferralRewards(weeks: 0, newReferrals: 0)
        }
        let client = SessionClient(config: config)
        guard let resp = try? await client.referralRewards(userId: userId) else {
            return ReferralRewards(weeks: 0, newReferrals: 0)
        }
        return ReferralRewards(weeks: resp.weeksOwed, newReferrals: resp.newReferrals)
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

        let reward = resp.refereeReward.map {
            ReferralReward(weeks: $0.weeks, label: $0.label)
        }
        return ReferralAttribution(
            alreadyAttributed: resp.alreadyAttributed ?? false,
            refereeReward: reward
        )
    }
    #endif
}
