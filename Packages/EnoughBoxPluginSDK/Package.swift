// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EnoughBoxPluginSDK",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EnoughBoxPluginSDK", type: .dynamic, targets: ["EnoughBoxPluginSDK"]),
    ],
    targets: [
        .target(name: "EnoughBoxPluginSDK"),
    ]
)
