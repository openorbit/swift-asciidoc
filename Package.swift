// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsciiDoc-Swift",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26)
        // Linux and Windows: handled implicitly by SwiftPM (no explicit declaration needed)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
      .library(name: "AsciiDocCore", targets: ["AsciiDocCore"]),
      .library(name: "AsciiDocRender", targets: ["AsciiDocRender"]),
      .library(name: "AsciiDocExtensions", targets: ["AsciiDocExtensions"]),
      .library(name: "AsciiDocTools", targets: ["AsciiDocTools"]),
      .library(name: "AsciiDocAntora", targets: ["AsciiDocAntora"]),

      .executable(name: "asciidoc-swift", targets: ["asciidoc-swift"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.0"),
        .package(url: "https://github.com/openorbit/swift-hunspell", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        // Core parsing/semantic engine (Foundation + RegexBuilder only)
        .target(
            name: "AsciiDocCore",
            dependencies: [],
            path: "Sources/AsciiDocCore",
            swiftSettings: [
                // Keep indexes Unicode-safe, discourage unsafe operations
                .enableExperimentalFeature("StrictConcurrency") // harmless on non-concurrency code
            ]
        ),
        .target(
            name: "AsciiDocRender",
            dependencies: [
                .product(name: "Stencil", package: "Stencil"),
                "AsciiDocCore",
            ],
            path: "Sources/AsciiDocRender",
            swiftSettings: [
                // Keep indexes Unicode-safe, discourage unsafe operations
                .enableExperimentalFeature("StrictConcurrency") // harmless on non-concurrency code
            ]
        ),

          .target(
              name: "AsciiDocExtensions",
              dependencies: ["AsciiDocCore"],
              path: "Sources/AsciiDocExtensions"
          ),
        .target(
            name: "AsciiDocTools",
            dependencies: [
                "AsciiDocCore",
                .product(name: "Hunspell", package: "swift-hunspell")
            ],
            path: "Sources/AsciiDocTools",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),


        .target(
            name: "AsciiDocAntora",
            dependencies: [
                "AsciiDocCore",
                "AsciiDocRender"
            ],
            path: "Sources/AsciiDocAntora"
        ),


        // CLI executable that the TCK will invoke
        .executableTarget(
            name: "asciidoc-swift",
            dependencies: [
                "AsciiDocCore",
                "AsciiDocRender",
                "AsciiDocExtensions",
                "AsciiDocTools",
                "AsciiDocAntora",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/asciidoc-swift",
            resources: [
                .copy("Templates")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),

        // Unit tests for the core; add fixture files under Tests/AsciiDocCoreTests/Fixtures as needed
        .testTarget(
            name: "AsciiDocCoreTests",
            dependencies: ["AsciiDocCore", "AsciiDocTools", "AsciiDocRender"],
            path: "Tests/AsciiDocCoreTests",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .testTarget(
            name: "TCK",
            dependencies: ["AsciiDocCore"],
            path: "Tests/TCK",
            resources: [.copy("tests")],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .testTarget(
            name: "AsciiDocAntoraTests",
            dependencies: ["AsciiDocAntora", "AsciiDocCore"],
            path: "Tests/AsciiDocAntoraTests",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        )
    ]
)
