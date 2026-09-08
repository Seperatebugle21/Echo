// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EchoNativeAudio",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(
            name: "CLame",
            targets: ["CLame"]
        )
    ],
    targets: [
        .target(
            name: "CLame",
            dependencies: ["mp3lame"],
            publicHeadersPath: "include"
        ),
        .binaryTarget(
            name: "mp3lame",
            url: "https://github.com/kewlbear/FFmpeg-iOS-Lame/releases/download/v0.0.6-b20230416-184420/mp3lame.zip",
            checksum: "c7b3ef1a5a5e8d8690389a1ae0b7c43368e90647590767fdede5d18a23e3bd22"
        )
    ]
)
