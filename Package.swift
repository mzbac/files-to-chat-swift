// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "files-to-chat-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "files-to-chat-swift", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.25.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples")
            ],
            path: "Sources/AppCore",
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedFramework("PDFKit"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "AppCore"
            ],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["AppCore"],
            path: "Tests/AppTests"
        )
    ]
)
