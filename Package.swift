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
    targets: [
        .executableTarget(
            name: "BenBenBen",
            path: "Sources/BenBenBen",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("WebKit")
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
