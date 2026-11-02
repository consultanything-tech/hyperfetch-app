// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FDM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DownloadKit",
            targets: ["DownloadKit"]
        ),
        .executable(
            name: "SwiftFlowApp",
            targets: ["SwiftFlowApp"]
        ),
    ],
    targets: [
        .target(
            name: "DownloadKit",
            path: "Sources/DownloadKit"
        ),
        .executableTarget(
            name: "SwiftFlowApp",
            dependencies: ["DownloadKit"],
            path: "Sources/SwiftFlowApp",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "DownloadKitTests",
            dependencies: ["DownloadKit"],
            path: "Tests/DownloadKitTests",
            swiftSettings: [
                .unsafeFlags([
                    "-load-plugin-library",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
                ])
            ]
        ),
    ]
)
