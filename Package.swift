// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipFlow", targets: ["ClipFlow"])
    ],
    targets: [
        .executableTarget(
            name: "ClipFlow",
            path: "Sources/ClipFlow"
        ),
        .testTarget(
            name: "ClipFlowTests",
            dependencies: ["ClipFlow"],
            path: "Tests/ClipFlowTests"
        )
    ]
)
