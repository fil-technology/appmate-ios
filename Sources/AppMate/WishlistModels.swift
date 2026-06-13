import Foundation

/// Lifecycle status of a wishlist idea. `pending` ideas are never returned by
/// the public API (they await owner approval), but the case exists so the enum
/// round-trips losslessly.
public enum WishlistStatus: String, Codable, Sendable {
    case pending
    case open
    case planned
    case in_progress
    case done
    case declined

    /// A human label suitable for a status chip.
    public var displayName: String {
        switch self {
        case .pending: "Pending"
        case .open: "Open"
        case .planned: "Planned"
        case .in_progress: "In progress"
        case .done: "Shipped"
        case .declined: "Declined"
        }
    }
}

/// One feature request on the board.
public struct WishlistIdea: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let body: String?
    public let category: String?
    public let status: WishlistStatus
    public var voteCount: Int
    public let commentCount: Int
    public let pinned: Bool
    /// Display name of the submitter, or "Anonymous".
    public let author: String
    /// ISO-8601 creation timestamp.
    public let createdAt: String
    /// Whether the current caller (resolved by userId / anonId) has voted.
    /// `nil` when identity couldn't be resolved for the request.
    public var hasVoted: Bool?
}

/// One comment on an idea.
public struct WishlistComment: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let body: String
    public let author: String
    /// True when posted by the app owner (shown with a "Team" badge).
    public let isOwner: Bool
    /// True when the owner flagged this as an authoritative response.
    public let isOfficial: Bool
    public let createdAt: String
}

/// A page of results plus the opaque cursor for the next page (nil = last page).
public struct WishlistPage<Item: Codable & Sendable>: Sendable {
    public let items: [Item]
    public let nextCursor: String?

    public init(items: [Item], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// How the board should order ideas.
public enum WishlistSort: String, Sendable {
    /// Most upvoted first (the default).
    case votes
    /// Newest first.
    case new
}
