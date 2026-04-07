// swift-tools-version: 6.0
//
// ManifoldCore – SwiftPackage/Package.swift
//
// Layer diagram:
//   ManifoldKit  (Swift, .interoperabilityMode(.Cxx))
//     └─ ManifoldBridge  (C++ – our thin wrapper, compiled by SPM)
//          └─ ManifoldBinary  (static XCFramework bootstrapped into vendor/)
//
// Linking strategy:
//   This package is self-contained once bootstrapped. Run:
//
//     make bootstrap
//
//   or:
//
//     Scripts/bootstrap-manifold.sh
//
//   to fetch/build the upstream Manifold C++ library and stage its headers
//   plus a multi-platform static XCFramework into vendor/.
//
// Layout:
//   Package.swift                  ← package root
//   Sources/ManifoldBridge/        ← C++ wrapper
//   Sources/ManifoldKit/           ← Swift API
//   Scripts/bootstrap-manifold.sh  ← builds + stages upstream Manifold
//   vendor/manifold-include/       ← staged public headers
//   vendor/ManifoldBinary.xcframework/ ← staged static library slices
import PackageDescription

let package = Package(
    name: "ManifoldCore",
    platforms: [
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "ManifoldKit", targets: ["ManifoldKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "ManifoldBinary",
            path: "vendor/ManifoldBinary.xcframework"
        ),

        // ── ManifoldBridge – C++ wrapper ──────────────────────────────────
        // Compiles our PIMPL wrapper against Manifold's public headers and
        // links the prebuilt static XCFramework slice selected by SwiftPM.
        .target(
            name: "ManifoldBridge",
            dependencies: ["ManifoldBinary"],
            path: "Sources/ManifoldBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../vendor/manifold-include"),
            ],
        ),

        // ── ManifoldKit – idiomatic Swift API ─────────────────────────────
        // C++ interop lets Swift import ManifoldBridge types directly.
        .target(
            name: "ManifoldKit",
            dependencies: ["ManifoldBridge"],
            path: "Sources/ManifoldKit",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
