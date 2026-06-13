import Foundation

/// Public data API for the feature-request wishlist board.
///
/// Unlike the cancel / onboarding / referral flows (which present a hosted web
/// UI in a Safari sheet), the wishlist exposes typed data so you can either:
///
///   • drop in the ready-made ``WishlistView`` SwiftUI screen, or
///   • build your own UI on top of these calls.
///
/// Identity: pass the host-app `userId` when you have one — votes and comments
/// are then deduped per user across devices. When you don't, the SDK generates
/// and persists an anonymous id (so a user still can't double-vote on the same
/// device), and the server additionally dedupes by hashed IP.
extension RetentionFlow {

    /// Stable anonymous id, persisted in UserDefaults, used when no `userId`
    /// is supplied. Exposed so custom UIs can reuse the same value.
    public static func wishlistAnonymousId() -> String {
        let key = "com.appmate.wishlist.anonId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private static func client() throws -> SessionClient {
        guard let config = RetentionFlow.config else { throw ConfigurationError.notConfigured }
        return SessionClient(config: config)
    }

    /// Resolve the identity pair to send: when `userId` is set we use it and
    /// omit anonId; otherwise we send the persisted anonId.
    private static func identity(_ userId: String?) -> (userId: String?, anonId: String?) {
        if let userId, !userId.isEmpty { return (userId, nil) }
        return (nil, wishlistAnonymousId())
    }

    /// Fetch a page of public ideas (never includes pending/unapproved ones).
    ///
    /// - Parameters:
    ///   - status: optional status filter (e.g. `.planned`). Omit for all public statuses.
    ///   - sort: `.votes` (default) or `.new`.
    ///   - cursor: pass the previous page's `nextCursor` to page forward.
    ///   - limit: page size (server clamps to ≤ 100).
    ///   - userId: host-app user id, when known.
    ///   - flowSlug: non-primary board slug; omit for the app's primary board.
    public static func wishlistIdeas(
        status: WishlistStatus? = nil,
        sort: WishlistSort = .votes,
        cursor: String? = nil,
        limit: Int? = nil,
        userId: String? = nil,
        flowSlug: String? = nil
    ) async throws -> WishlistPage<WishlistIdea> {
        let ids = identity(userId)
        let res = try await client().fetchWishlistIdeas(
            flowSlug: flowSlug,
            status: status?.rawValue,
            sort: sort.rawValue,
            cursor: cursor,
            limit: limit,
            userId: ids.userId,
            anonId: ids.anonId
        )
        return WishlistPage(items: res.ideas, nextCursor: res.nextCursor)
    }

    /// Submit a new idea. By default it lands in the owner's pending queue and
    /// won't appear on the board until approved; the returned tuple's
    /// `pending` flag tells you which happened.
    public static func submitWishlistIdea(
        title: String,
        body: String? = nil,
        category: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        userId: String? = nil,
        flowSlug: String? = nil
    ) async throws -> (idea: WishlistIdea, pending: Bool) {
        let ids = identity(userId)
        let res = try await client().submitWishlistIdea(
            flowSlug: flowSlug,
            title: title,
            body: body,
            category: category,
            email: email,
            displayName: displayName,
            userId: ids.userId,
            anonId: ids.anonId
        )
        return (res.idea, res.pending)
    }

    /// Upvote an idea. Idempotent — voting twice is a no-op. Returns the new
    /// vote count.
    @discardableResult
    public static func voteWishlistIdea(
        ideaId: String,
        email: String? = nil,
        userId: String? = nil,
        flowSlug: String? = nil
    ) async throws -> Int {
        let ids = identity(userId)
        let res = try await client().voteWishlistIdea(
            flowSlug: flowSlug,
            ideaId: ideaId,
            remove: false,
            userId: ids.userId,
            anonId: ids.anonId,
            email: email
        )
        return res.voteCount
    }

    /// Remove the caller's vote from an idea. Returns the new vote count.
    @discardableResult
    public static func unvoteWishlistIdea(
        ideaId: String,
        email: String? = nil,
        userId: String? = nil,
        flowSlug: String? = nil
    ) async throws -> Int {
        let ids = identity(userId)
        let res = try await client().voteWishlistIdea(
            flowSlug: flowSlug,
            ideaId: ideaId,
            remove: true,
            userId: ids.userId,
            anonId: ids.anonId,
            email: email
        )
        return res.voteCount
    }

    /// Fetch a page of comments on an idea (oldest-first).
    public static func wishlistComments(
        ideaId: String,
        cursor: String? = nil,
        limit: Int? = nil,
        flowSlug: String? = nil
    ) async throws -> WishlistPage<WishlistComment> {
        let res = try await client().fetchWishlistComments(
            flowSlug: flowSlug,
            ideaId: ideaId,
            cursor: cursor,
            limit: limit
        )
        return WishlistPage(items: res.comments, nextCursor: res.nextCursor)
    }

    /// Post a comment on an idea as the end user.
    @discardableResult
    public static func postWishlistComment(
        ideaId: String,
        body: String,
        email: String? = nil,
        displayName: String? = nil,
        userId: String? = nil,
        flowSlug: String? = nil
    ) async throws -> WishlistComment {
        let ids = identity(userId)
        let res = try await client().postWishlistComment(
            flowSlug: flowSlug,
            ideaId: ideaId,
            body: body,
            email: email,
            displayName: displayName,
            userId: ids.userId,
            anonId: ids.anonId
        )
        return res.comment
    }
}
