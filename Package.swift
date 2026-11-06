// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KaiOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Kai OS",
            targets: ["KaiOS"]
        )
    ],
    targets: [
        .target(
            name: "KaiLocalAI",
            path: "KaiLocalAI"
        ),
        .target(
            name: "KaiActions",
            dependencies: ["KaiLocalAI", "KaiLocalData"],
            path: "KaiActions"
        ),
        .target(
            name: "KaiCapture",
            path: "KaiCapture"
        ),
        .target(
            name: "KaiLocalData",
            path: "KaiLocalData"
        ),
        .target(
            name: "KaiNotchCore",
            path: "KaiNotchCore"
        ),
        .executableTarget(
            name: "KaiOS",
            dependencies: ["KaiActions", "KaiCapture", "KaiLocalAI", "KaiLocalData", "KaiNotchCore"],
            path: "Kai OS macOS",
            exclude: ["Info.plist", "Info.plist.template"]
        ),
        .executableTarget(
            name: "KaiLocalAIChecks",
            dependencies: ["KaiActions", "KaiCapture", "KaiLocalAI", "KaiLocalData", "KaiNotchCore"],
            path: "KaiLocalAIChecks"
        )
    ]
)
