// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Flick", targets: ["Flick"])],
    targets: [
        .target(name: "FlickCore"),
        .executableTarget(name: "Flick", dependencies: ["FlickCore"]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"])
    ],
    swiftLanguageModes: [.v5]
)
