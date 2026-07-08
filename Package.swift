// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CraftQuickCapture",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CraftQuickCapture",
            path: "Sources",
            exclude: [],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
