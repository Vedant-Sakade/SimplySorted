// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TidyUp",
    platforms: [.macOS("14.0")],
    products: [
        .executable(name: "TidyUp", targets: ["TidyUp"]),
        .library(name: "TidyCore", targets: ["TidyCore"]),
    ],
    targets: [
        // File-sorting engine: rules, planning, moving, undo. No UI, so it is easy to test.
        .target(name: "TidyCore"),
        // The SwiftUI Mac app (window + menu bar item).
        .executableTarget(name: "TidyUp", dependencies: ["TidyCore"]),
        .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore"]),
    ]
)
