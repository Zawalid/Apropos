// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Apropos",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Apropos", targets: ["Apropos"]),
        .executable(name: "apropos-probe", targets: ["AproposProbe"]),
    ],
    targets: [
        .target(
            name: "Apropos",
            resources: [
                .copy("Resources/SymbolPacks"), .copy("Resources/ActionPacks"), .copy("Resources/DestinationPacks"),
            ]),
        .executableTarget(name: "AproposProbe", dependencies: ["Apropos"], path: "Sources/apropos-probe"),
        .testTarget(name: "AproposTests", dependencies: ["Apropos"]),
    ]
)
