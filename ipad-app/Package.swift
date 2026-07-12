// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KalpanaDrive",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KalpanaDriveCore", targets: ["KalpanaDriveCore"]),
        .executable(name: "KalpanaDriveApp", targets: ["KalpanaDriveApp"]),
        .executable(name: "KalpanaDriveChecks", targets: ["KalpanaDriveChecks"])
    ],
    targets: [
        .target(name: "KalpanaDriveCore"),
        .executableTarget(
            name: "KalpanaDriveApp",
            dependencies: ["KalpanaDriveCore"]
        ),
        .executableTarget(
            name: "KalpanaDriveChecks",
            dependencies: ["KalpanaDriveCore"],
            path: "Tests/KalpanaDriveCoreTests"
        )
    ]
)
