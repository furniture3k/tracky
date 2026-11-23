// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tracky",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tracky",
            path: "Sources/Tracky",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))]
        ),
        .testTarget(name: "TrackyTests", dependencies: ["Tracky"], path: "Tests/TrackyTests"),
    ]
)
