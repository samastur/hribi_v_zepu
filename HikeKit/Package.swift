// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HikeKit",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "HikeKit", targets: ["HikeKit"])],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        .target(name: "HikeKit", dependencies: ["SwiftSoup"]),
        .testTarget(
            name: "HikeKitTests",
            dependencies: ["HikeKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
