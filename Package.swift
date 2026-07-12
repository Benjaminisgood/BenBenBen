// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BenBenBen",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "BenBenBen", targets: ["BenBenBen"]),
        .executable(name: "BenBenBenLoginHelper", targets: ["BenBenBenLoginHelper"])
    ],
    dependencies: [
        .package(path: "Vendor/swift-markdown-engine")
    ],
    targets: [
        .executableTarget(
            name: "BenBenBen",
            dependencies: [
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
                .product(name: "MarkdownEngineLatex", package: "swift-markdown-engine")
            ],
            path: "Sources/BenBenBen",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "BenBenBenLoginHelper",
            path: "Sources/BenBenBenLoginHelper",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "BenBenBenTests",
            dependencies: ["BenBenBen"],
            path: "Tests/BenBenBenTests"
        )
    ]
)
