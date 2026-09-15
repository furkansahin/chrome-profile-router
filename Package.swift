// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChromeProfileRouter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ChromeProfileRouter", targets: ["ChromeProfileRouter"])],
    targets: [
        .target(name: "RouterCore"),
        .executableTarget(name: "ChromeProfileRouter", dependencies: ["RouterCore"]),
        .testTarget(name: "RouterCoreTests", dependencies: ["RouterCore"])
    ],
    swiftLanguageModes: [.v5]
)
