// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Cue", targets: ["Cue"]),
        .executable(name: "cue-probe", targets: ["CueProbe"]),
    ],
    targets: [
        .target(name: "Cue"),
        .executableTarget(name: "CueProbe", dependencies: ["Cue"], path: "Sources/cue-probe"),
        .testTarget(name: "CueTests", dependencies: ["Cue"]),
    ]
)
