// UIKit gate (not just SwiftUI) so this iOS-only screen is excluded on macOS,
// where the iOS 16 availability annotations wouldn't cover the platform.
#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// WishlistView — a ready-made feature-request board you can drop into your app:
//
//     WishlistView(userId: currentUser?.id)
//
// Embed it in a tab, push it onto a navigation stack, or present it as a sheet.
// It uses the public RetentionFlow wishlist API under the hood; if you'd rather
// build your own UI, call those methods directly (see RetentionFlowWishlistAPI).
//
// Requires RetentionFlow.configure(_:) to have run. iOS 16+.
// ─────────────────────────────────────────────────────────────────────────────

@available(iOS 16.0, *)
public struct WishlistView: View {
    private let userId: String?
    private let flowSlug: String?
    /// Collected once when email-gated flows demand it; reused for the session.
    @State private var email: String = ""

    @StateObject private var store: WishlistStore
    @State private var showSubmit = false
    @State private var selected: WishlistIdea?

    public init(userId: String? = nil, flowSlug: String? = nil) {
        self.userId = userId
        self.flowSlug = flowSlug
        _store = StateObject(wrappedValue: WishlistStore(userId: userId, flowSlug: flowSlug))
    }

    public var body: some View {
        List {
            Picker("Sort", selection: $store.sort) {
                Text("Top").tag(WishlistSort.votes)
                Text("New").tag(WishlistSort.new)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .onChange(of: store.sort) { _ in Task { await store.reload() } }

            if store.ideas.isEmpty && !store.loading {
                Text("No ideas yet — be the first to suggest one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowSeparator(.hidden)
            }

            ForEach(store.ideas) { idea in
                Button { selected = idea } label: {
                    WishlistRow(idea: idea) { Task { await store.toggleVote(idea) } }
                }
                .buttonStyle(.plain)
            }

            if store.nextCursor != nil {
                Button {
                    Task { await store.loadMore() }
                } label: {
                    HStack {
                        Spacer()
                        if store.loading { ProgressView() } else { Text("Load more") }
                        Spacer()
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.loading && store.ideas.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Feature requests")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSubmit = true
                } label: {
                    Label("Suggest", systemImage: "plus")
                }
            }
        }
        .refreshable { await store.reload() }
        .task { if store.ideas.isEmpty { await store.reload() } }
        .sheet(isPresented: $showSubmit) {
            WishlistSubmitView(userId: userId, flowSlug: flowSlug) { newIdea, pending in
                if !pending { store.prepend(newIdea) }
            }
        }
        .sheet(item: $selected) { idea in
            WishlistIdeaDetailView(
                idea: idea,
                userId: userId,
                flowSlug: flowSlug,
                onVoteChanged: { store.replace($0) }
            )
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.error != nil },
            set: { if !$0 { store.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.error ?? "")
        }
    }
}

// MARK: - Row

@available(iOS 16.0, *)
struct WishlistRow: View {
    let idea: WishlistIdea
    let onVote: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VoteBadge(count: idea.voteCount, voted: idea.hasVoted ?? false, action: onVote)
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title).font(.headline)
                if let body = idea.body, !body.isEmpty {
                    Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    WishlistStatusBadge(status: idea.status)
                    if let category = idea.category {
                        Text(category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("\(idea.commentCount)", systemImage: "bubble.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

@available(iOS 16.0, *)
struct VoteBadge: View {
    let count: Int
    let voted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: voted ? "chevron.up.circle.fill" : "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                Text("\(count)").font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 44)
            .padding(.vertical, 8)
            .background(voted ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
            .foregroundStyle(voted ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 16.0, *)
struct WishlistStatusBadge: View {
    let status: WishlistStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .pending: .orange
        case .open: .blue
        case .planned: .purple
        case .in_progress: .indigo
        case .done: .green
        case .declined: .gray
        }
    }
}

// MARK: - Submit

@available(iOS 16.0, *)
struct WishlistSubmitView: View {
    let userId: String?
    let flowSlug: String?
    let onSubmitted: (WishlistIdea, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var submitting = false
    @State private var error: String?
    @State private var doneMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let doneMessage {
                    Section { Text(doneMessage).foregroundStyle(.secondary) }
                } else {
                    Section("Your idea") {
                        TextField("A short, clear title", text: $title)
                        TextField("Add detail (optional)", text: $detail, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    Section("About you (optional)") {
                        TextField("Name", text: $displayName)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Suggest a feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(doneMessage == nil ? "Cancel" : "Done") { dismiss() }
                }
                if doneMessage == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { Task { await submit() } }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || submitting)
                    }
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        error = nil
        do {
            let (idea, pending) = try await RetentionFlow.submitWishlistIdea(
                title: title,
                body: detail.isEmpty ? nil : detail,
                email: email.isEmpty ? nil : email,
                displayName: displayName.isEmpty ? nil : displayName,
                userId: userId,
                flowSlug: flowSlug
            )
            onSubmitted(idea, pending)
            doneMessage = pending
                ? "Thanks — your idea is in. We review new ideas before they appear on the board."
                : "Thanks — your idea is now on the board."
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

// MARK: - Detail + comments

@available(iOS 16.0, *)
struct WishlistIdeaDetailView: View {
    let idea: WishlistIdea
    let userId: String?
    let flowSlug: String?
    let onVoteChanged: (WishlistIdea) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current: WishlistIdea
    @State private var comments: [WishlistComment] = []
    @State private var nextCursor: String?
    @State private var loading = true
    @State private var draft = ""
    @State private var posting = false
    @State private var error: String?

    init(
        idea: WishlistIdea,
        userId: String?,
        flowSlug: String?,
        onVoteChanged: @escaping (WishlistIdea) -> Void
    ) {
        self.idea = idea
        self.userId = userId
        self.flowSlug = flowSlug
        self.onVoteChanged = onVoteChanged
        _current = State(initialValue: idea)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VoteBadge(count: current.voteCount, voted: current.hasVoted ?? false) {
                            Task { await toggleVote() }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(current.title).font(.title3.weight(.semibold))
                            HStack(spacing: 8) {
                                WishlistStatusBadge(status: current.status)
                                Text(current.author).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let body = current.body, !body.isEmpty {
                        Text(body).font(.body)
                    }

                    Divider()

                    Text("Comments").font(.headline)
                    if loading {
                        ProgressView()
                    } else if comments.isEmpty {
                        Text("No comments yet.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(comments) { WishlistCommentRow(comment: $0) }
                        if nextCursor != nil {
                            Button("Load more comments") { Task { await loadComments(reset: false) } }
                                .font(.subheadline)
                        }
                    }

                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button {
                        Task { await postComment() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || posting)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadComments(reset: true) }
        }
    }

    private func toggleVote() async {
        let willVote = !(current.hasVoted ?? false)
        do {
            let count = willVote
                ? try await RetentionFlow.voteWishlistIdea(ideaId: current.id, userId: userId, flowSlug: flowSlug)
                : try await RetentionFlow.unvoteWishlistIdea(ideaId: current.id, userId: userId, flowSlug: flowSlug)
            current.voteCount = count
            current.hasVoted = willVote
            onVoteChanged(current)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadComments(reset: Bool) async {
        if reset { loading = true }
        do {
            let page = try await RetentionFlow.wishlistComments(
                ideaId: current.id,
                cursor: reset ? nil : nextCursor,
                flowSlug: flowSlug
            )
            comments = reset ? page.items : comments + page.items
            nextCursor = page.nextCursor
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func postComment() async {
        posting = true
        error = nil
        do {
            let comment = try await RetentionFlow.postWishlistComment(
                ideaId: current.id,
                body: draft,
                userId: userId,
                flowSlug: flowSlug
            )
            comments.append(comment)
            draft = ""
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        posting = false
    }
}

@available(iOS 16.0, *)
struct WishlistCommentRow: View {
    let comment: WishlistComment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.author).font(.caption.weight(.semibold))
                if comment.isOwner {
                    Text(comment.isOfficial ? "Official" : "Team")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary)
                        .foregroundStyle(Color(.systemBackground))
                        .clipShape(Capsule())
                }
            }
            Text(comment.body).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(comment.isOwner ? Color(.secondarySystemBackground) : Color(.systemBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Store

@available(iOS 16.0, *)
@MainActor
final class WishlistStore: ObservableObject {
    @Published var ideas: [WishlistIdea] = []
    @Published var sort: WishlistSort = .votes
    @Published var loading = false
    @Published var nextCursor: String?
    @Published var error: String?

    private let userId: String?
    private let flowSlug: String?

    init(userId: String?, flowSlug: String?) {
        self.userId = userId
        self.flowSlug = flowSlug
    }

    func reload() async {
        loading = true
        error = nil
        do {
            let page = try await RetentionFlow.wishlistIdeas(
                sort: sort, userId: userId, flowSlug: flowSlug
            )
            ideas = page.items
            nextCursor = page.nextCursor
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    func loadMore() async {
        guard let cursor = nextCursor, !loading else { return }
        loading = true
        do {
            let page = try await RetentionFlow.wishlistIdeas(
                sort: sort, cursor: cursor, userId: userId, flowSlug: flowSlug
            )
            ideas += page.items
            nextCursor = page.nextCursor
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    func toggleVote(_ idea: WishlistIdea) async {
        guard let idx = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        let willVote = !(ideas[idx].hasVoted ?? false)
        // Optimistic.
        ideas[idx].hasVoted = willVote
        ideas[idx].voteCount += willVote ? 1 : -1
        do {
            let count = willVote
                ? try await RetentionFlow.voteWishlistIdea(ideaId: idea.id, userId: userId, flowSlug: flowSlug)
                : try await RetentionFlow.unvoteWishlistIdea(ideaId: idea.id, userId: userId, flowSlug: flowSlug)
            if let i = ideas.firstIndex(where: { $0.id == idea.id }) {
                ideas[i].voteCount = count
                ideas[i].hasVoted = willVote
            }
        } catch {
            // Roll back.
            if let i = ideas.firstIndex(where: { $0.id == idea.id }) {
                ideas[i].hasVoted = idea.hasVoted
                ideas[i].voteCount = idea.voteCount
            }
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func prepend(_ idea: WishlistIdea) {
        ideas.insert(idea, at: 0)
    }

    func replace(_ idea: WishlistIdea) {
        if let i = ideas.firstIndex(where: { $0.id == idea.id }) {
            ideas[i] = idea
        }
    }
}
#endif
