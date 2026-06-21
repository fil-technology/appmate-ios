// swift-tools-version: 5.9
// AppMate iOS SDK — Swift Package
import PackageDescription

let package = Package(
    name: "AppMate",
    platforms: [
        .iOS(.v16),
        // macOS: the networking core, referral, onboarding-claim, wishlist API,
        // and deep-link parsing are cross-platform. The in-app flow presentation
        // (SFSafariViewController), the wishlist view, and shake-to-report stay
        // iOS-only behind `#if canImport(UIKit)`. v13 covers the async URLSession
        // APIs the SDK uses.
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AppMate",
            targets: ["AppMate"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppMate",
            path: "Sources/AppMate"
        ),
        .testTarget(
            name: "AppMateTests",
            dependencies: ["AppMate"],
            path: "Tests/AppMateTests"
        )
    ]
)
