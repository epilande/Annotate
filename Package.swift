// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "Annotate",
    platforms: [
        .macOS(.v13)  // Adjust as needed
    ],
    products: [
        // An executable product, so SwiftPM tries to compile and link all files under the target.
        .executable(name: "Annotate", targets: ["Annotate"])
    ],
    dependencies: [
        // Declare any package dependencies here.
        // e.g. .package(url: "https://github.com/...", from: "1.2.3")
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.4")
    ],
    targets: [
        .executableTarget(
            name: "Annotate",
            dependencies: ["KeyboardShortcuts"],
            path: "Annotate",
            resources: []
        )
    ]
)
