// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Jian",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Jian", targets: ["ClipFlow"])
    ],
    targets: [
        .executableTarget(
            name: "ClipFlow",
            path: "Sources/ClipFlow",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ClipFlowTests",
            dependencies: ["ClipFlow"],
            path: "Tests/ClipFlowTests"
        )
    ]
)
