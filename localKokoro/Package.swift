// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "localKokoro",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "localKokoro",
            targets: ["localKokoro"]
        ),
    ],
    dependencies: [
        .package(path: "../core"),
        .package(url: "https://github.com/mlalma/kokoro-ios", exact: "1.0.11"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        .target(
            name: "localKokoro",
            dependencies: [
                .product(name: "core", package: "core"),
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
            ]
        ),
        .testTarget(
            name: "localKokoroTests",
            dependencies: ["localKokoro"]
        ),
    ]
)
