// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Flick", targets: ["Flick"])],
    targets: [
        .target(name: "FlickCore"),
        .target(name: "SkyLightBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
        .executableTarget(name: "Flick", dependencies: ["FlickCore", "SkyLightBridge"]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
        .testTarget(name: "FlickTests", dependencies: ["Flick"])
    ],
    swiftLanguageModes: [.v5]
)
