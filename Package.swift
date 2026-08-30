// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mousetrapped",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Mousetrapped",
            path: "Sources/Mousetrapped"
        )
    ]
)
