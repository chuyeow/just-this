// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JustThis",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "JustThisCore"),
        .executableTarget(name: "JustThis", dependencies: ["JustThisCore"]),
        .testTarget(name: "JustThisCoreTests", dependencies: ["JustThisCore"]),
        .testTarget(name: "JustThisTests", dependencies: ["JustThis", "JustThisCore"]),
    ]
)
