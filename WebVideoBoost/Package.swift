// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebVideoBoost",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "WebVideoBoost", targets: ["WebVideoBoost"]),
    ],
    targets: [
        .target(
            name: "WebVideoBoost",
            path: "Sources/WebVideoBoost",
            resources: [
                .copy("VideoPiP/video_pip.js"),
                .copy("BackgroundPlayback/background_playback.js"),
                .copy("AdBlock/cosmetic.js"),
                .copy("AdBlock/youtube_adskip.js"),
                .copy("AdBlock/Lists"),
            ]
        ),
        .testTarget(
            name: "WebVideoBoostTests",
            dependencies: ["WebVideoBoost"],
            path: "Tests/WebVideoBoostTests"
        ),
    ]
)
