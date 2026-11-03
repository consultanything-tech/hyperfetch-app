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
            name: "HyperFetch",
            targets: ["HyperFetchApp"]
        ),
    ],
    targets: [
        .target(
            name: "DownloadKit",
            path: "Sources/DownloadKit"
        ),
        .executableTarget(
            name: "HyperFetchApp",
            dependencies: ["DownloadKit"],
            path: "Sources/HyperFetchApp",
            exclude: ["Info.plist", "Resources", "HyperFetch.entitlements"]
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
