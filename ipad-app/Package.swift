// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KalpanaDriveCorePackage",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KalpanaDriveCore", targets: ["KalpanaDriveCore"]),
        .executable(name: "KalpanaDriveChecks", targets: ["KalpanaDriveChecks"])
    ],
    targets: [
        .target(name: "KalpanaDriveCore"),
        .executableTarget(
            name: "KalpanaDriveChecks",
            dependencies: ["KalpanaDriveCore"],
            path: "Tests/KalpanaDriveCoreTests"
        )
    ]
)
