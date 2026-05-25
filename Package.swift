// swift-tools-version: 5.9
// AppMate iOS SDK — Swift Package
import PackageDescription

let package = Package(
    name: "AppMate",
    platforms: [
        .iOS(.v16)
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
