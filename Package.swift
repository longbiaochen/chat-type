// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ChatType",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "ChatType", targets: ["ChatType"]),
    ],
    targets: [
        .executableTarget(
            name: "ChatType",
            path: "Sources/VoiceDex"
        ),
        .testTarget(
            name: "ChatTypeTests",
            dependencies: ["ChatType"],
            path: "Tests/VoiceDexTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
