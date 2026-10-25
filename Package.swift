// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicSift",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PicSift", targets: ["PicSift"])
    ],
    targets: [
        .executableTarget(
            name: "PicSift",
            path: "Sources/PicSift",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
