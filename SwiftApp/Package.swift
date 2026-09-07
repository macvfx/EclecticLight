// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EclecticLightUpdater",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EclecticLightUpdater",
            path: "Sources/EclecticLightUpdater"
        ),
        .testTarget(name: "EclecticLightUpdaterTests", dependencies: ["EclecticLightUpdater"])
    ]
)