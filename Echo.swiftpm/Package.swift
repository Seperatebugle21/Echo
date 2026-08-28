// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes


let package = Package(

    name: "Echo",

    defaultLocalization: "en",

    platforms: [
        .iOS("26.0")
    ],

    products: [

        .iOSApplication(

            name: "Echo",

            targets: [
                "AppModule"
            ],

            bundleIdentifier:
                "com.echomusic.app",

            displayVersion:
                "1.0",

            bundleVersion:
                "1",

            appIcon:
                .asset("AppIcon"),

            accentColor:
                .presetColor(.red),

            supportedDeviceFamilies: [
                .pad,
                .phone
            ],

            supportedInterfaceOrientations: [

                .portrait,

                .portraitUpsideDown(
                    .when(
                        deviceFamilies: [
                            .pad
                        ]
                    )
                )
            ],

            capabilities: [

                .mediaLibrary(
                    purposeString:
                        "Used to add music from local files or Apple Music to Echo"
                ),

                .bluetoothAlways(
                    purposeString:
                        "Used to connect to external devices like headphones or speakers"
                )
            ]
        )
    ],


    // MARK: - Packages

    dependencies: [

        // =========================================
        // YoutubeDL-iOS
        // =========================================

        .package(
            url:
                "https://github.com/Seperatebugle21/YoutubeDL-iOS.git",

            branch:
                "main"
        ),


        // =========================================
        // PythonKit
        // =========================================

        .package(
            url:
                "https://github.com/pvieito/PythonKit.git",

            exact:
                "0.5.1"
        ),


        // =========================================
        // Python-iOS
        // =========================================

        .package(
            url:
                "https://github.com/kewlbear/Python-iOS.git",

            exact:
                "0.1.1-b20230423-090254"
        )
    ],


    // MARK: - Targets

    targets: [

        // =========================================
        // Echo
        // =========================================

        .executableTarget(

            name:
                "AppModule",

            dependencies: [

                .product(
                    name:
                        "YoutubeDL",

                    package:
                        "YoutubeDL-iOS"
                ),

                .product(
                    name:
                        "PythonKit",

                    package:
                        "PythonKit"
                ),

                .product(
                    name:
                        "Python-iOS",

                    package:
                        "Python-iOS"
                ),


                // IMPORTANT:
                //
                // Dit is ALLEEN libmp3lame.
                //
                // Geen:
                // - fftools
                // - ffmpeg
                // - ffprobe
                // - avcodec
                //
                // Daardoor krijgen we niet opnieuw
                // de duplicate symbols van eerder.

                "mp3lame"
            ],

            path:
                ".",

            swiftSettings: [

                .enableUpcomingFeature(
                    "BareSlashRegexLiterals"
                ),

                .unsafeFlags(
                    [
                        "-Onone"
                    ],

                    .when(
                        configuration:
                            .release
                    )
                )
            ]
        ),


        // =========================================
        // Standalone LAME binary
        // =========================================

        .binaryTarget(

            name:
                "mp3lame",

            url:
                "https://github.com/kewlbear/FFmpeg-iOS-Lame/releases/download/v0.0.6-b20230416-184420/mp3lame.zip",

            checksum:
                "c7b3ef1a5a5e8d8690389a1ae0b7c43368e90647590767fdede5d18a23e3bd22"
        )
    ]
)
