// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "unheardpath",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        // Mapbox Maps SDK
        .package(url: "https://github.com/mapbox/mapbox-maps-ios", from: "11.14.4"),
        // Supabase Swift client
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.31.2"),
        // Swift ASN.1
        .package(url: "https://github.com/apple/swift-asn1", from: "1.4.0"),
        // Swift Clocks
        .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.6"),
        // Swift Concurrency Extras
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.2"),
        // Swift Crypto
        .package(url: "https://github.com/apple/swift-crypto", from: "3.15.0"),
        // Swift HTTP Types
        .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
        // Turf
        .package(url: "https://github.com/mapbox/turf-swift", from: "4.0.0"),
        // XCTest Dynamic Overlay
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.6.1"),
        // MarkdownUI
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.2.0")
    ],
    targets: [
        .target(
            name: "unheardpath",
            dependencies: [
                .product(name: "MapboxMaps", package: "mapbox-maps-ios"),
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Turf", package: "turf-swift"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        )
    ]
)