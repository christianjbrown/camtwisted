// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CamTwistCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CamTwistCore", targets: ["CamTwistCore"]),
        .library(name: "CamTwistRendering", targets: ["CamTwistRendering"]),
        .library(name: "CamTwistControl", targets: ["CamTwistControl"]),
    ],
    targets: [
        .target(name: "CamTwistCore"),
        // The virtual microphone's audio driver, in C. The app's build
        // wraps it in the bundle the audio server loads.
        .target(
            name: "CamTwistAudioDriver",
            linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("CoreFoundation")]
        ),
        .target(name: "CamTwistRendering", dependencies: ["CamTwistCore"]),
        .target(name: "CamTwistControl", dependencies: ["CamTwistCore", "CamTwistRendering"]),
        .testTarget(name: "CamTwistCoreTests", dependencies: ["CamTwistCore"]),
        .testTarget(name: "CamTwistAudioDriverTests", dependencies: ["CamTwistAudioDriver", "CamTwistCore"]),
        .testTarget(name: "CamTwistRenderingTests", dependencies: ["CamTwistRendering"]),
        .testTarget(name: "CamTwistControlTests", dependencies: ["CamTwistControl", "CamTwistCore", "CamTwistRendering"]),
    ]
)
