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

    dependencies: [

        // MARK: YoutubeDL-iOS

        .package(
            url:
                "https://github.com/Seperatebugle21/YoutubeDL-iOS.git",
            branch:
                "main"
        ),


        // MARK: PythonKit
        //
        // Exact dezelfde versie als FreeTube.

        .package(
            url:
                "https://github.com/pvieito/PythonKit.git",
            exact:
                "0.5.1"
        ),


        // MARK: Python-iOS
        //
        // Expliciete dependency.
        //
        // Hiermee zorgen we ervoor dat de Python binary targets
        // én PythonSupport resource bundle rechtstreeks onderdeel
        // worden van Echo's app dependency graph.

        .package(
            url:
                "https://github.com/kewlbear/Python-iOS.git",
            exact:
                "0.1.1-b20230423-090254"
        )
    ],

    targets: [

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

                // IMPORTANT:
                //
                // Product heet "Python-iOS".
                //
                // "PythonSupport" is GEEN product.
                // Dat was een fout in een eerdere poging.

                .product(
                    name:
                        "Python-iOS",
                    package:
                        "Python-iOS"
                )
            ],

            path:
                ".",

            swiftSettings: [

                .enableUpcomingFeature(
                    "BareSlashRegexLiterals"
                ),

                // FreeTube draait zijn Release app-target
                // eveneens zonder Swift optimalisatie.

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
        )
    ]
)
