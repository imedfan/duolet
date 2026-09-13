// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoletCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DuoletCore", targets: ["DuoletCore"])],
    targets: [
        .target(name: "DuoletCore", path: "Sources/Shared"),
        .testTarget(name: "DuoletCoreTests", dependencies: ["DuoletCore"])
    ],
    swiftLanguageModes: [.v5]
)
