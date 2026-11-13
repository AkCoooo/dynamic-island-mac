// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DynamicIslandMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DynamicIslandMac",
            path: "Sources/DynamicIslandMac",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
