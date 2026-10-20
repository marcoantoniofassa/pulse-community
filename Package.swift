// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Pulse",
            path: "Sources/Pulse",
            swiftSettings: [
                // Mantem o codigo legado (escrito em Swift 5) compilando sem
                // strict concurrency virar erro. O engine novo respeita a licao
                // do spike (drain fora do MainActor) por construcao.
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Speech"),
            ]
        )
    ]
)
