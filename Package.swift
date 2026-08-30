// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NODAYSIDLEVoice",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NODAYSIDLEVoice", targets: ["NODAYSIDLEVoice"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "NODAYSIDLEVoice",
            dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")]
        ),
        .testTarget(name: "NODAYSIDLEVoiceTests", dependencies: ["NODAYSIDLEVoice"]),
    ]
)
