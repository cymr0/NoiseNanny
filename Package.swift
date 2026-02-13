// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoiseNanny",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NoiseNanny",
            path: "Sources"
        ),
        .testTarget(
            name: "NoiseNannyTests",
            dependencies: ["NoiseNanny"],
            path: "Tests/NoiseNannyTests"
        )
    ]
)
