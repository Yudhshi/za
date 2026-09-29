// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Nippo",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "NippoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NippoApp",
            dependencies: ["NippoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "nippo-tests",
            dependencies: ["NippoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
