// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "lidlezz",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lidlezz", targets: ["lidlezz"]),
        .executable(name: "LidlezzApp", targets: ["LidlezzApp"]),
        .executable(name: "LidlezzHelper", targets: ["LidlezzHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(name: "LidlezzCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "lidlezz", dependencies: ["LidlezzCore"]),
        .executableTarget(name: "LidlezzHelper", dependencies: ["LidlezzCore"]),
        .executableTarget(name: "LidlezzApp", dependencies: ["LidlezzCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources")]),
    ],
    swiftLanguageVersions: [.v5]
)
