// A minimal SwiftUI app demonstrating AppMate integration.
//
// To run:
//   1. Add this folder as a target in an Xcode project, OR drop the file into
//      a new SwiftUI app project.
//   2. Add `AppMate` as a Swift Package dependency (this repo).
//   3. Update `appSlug` and `baseURL` below to match your AppMate dashboard.
//   4. Register `myapp` as a CFBundleURLScheme in your Info.plist.

import SwiftUI
import AppMate

@main
struct RetentionFlowDemoApp: App {
    init() {
        RetentionFlow.configure(
            .init(
                appSlug: "my-ios-app",
                baseURL: URL(string: "https://cancel.appmate.cloud")!,
                urlScheme: "myapp"
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var lastAction: String = "—"
    @State private var showWishlist = false

    var body: some View {
        VStack(spacing: 16) {
            Text("AppMate demo")
                .font(.title2)
            Text("Last action: \(lastAction)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Cancel subscription") {
                RetentionFlow.startCancelFlow(
                    userId: "demo-user-1",
                    attributes: ["plan": "monthly"]
                ) { link in
                    handle(link)
                }
            }
            .buttonStyle(.borderedProminent)

            // Drop-in native feature-request board. Present it however you like
            // — here as a sheet; it also works pushed on a stack or in a tab.
            // Pass your real user id for cross-device vote/comment dedup.
            Button("Feature wishlist") { showWishlist = true }
                .buttonStyle(.bordered)
        }
        .padding()
        .sheet(isPresented: $showWishlist) {
            NavigationStack {
                WishlistView(userId: "demo-user-1")
            }
        }
        .onOpenURL { url in
            if let link = RetentionFlow.deepLink(from: url) {
                handle(link)
            }
        }
        .task {
            // Raw-data API example — build your own UI on top of these calls.
            if let page = try? await RetentionFlow.wishlistIdeas(sort: .votes) {
                print("Top idea:", page.items.first?.title ?? "none")
            }
        }
    }

    @MainActor
    private func handle(_ link: RetentionFlowDeepLink) {
        switch link.action {
        case .returnToApp: lastAction = "return_to_app"
        case .openPremium: lastAction = "open_premium → show paywall"
        case .openSupport: lastAction = "open_support → show support inbox"
        case .openFeature(let id): lastAction = "open_feature: \(id)"
        case .externalURL(let url):
            lastAction = "external_url: \(url)"
            UIApplication.shared.open(url)
        case .manageSubscription:
            lastAction = "manage_subscription → StoreKit sheet"
            Task { await RetentionFlow.presentManageSubscriptions() }
        case .none:
            lastAction = "none"
        }
    }
}
