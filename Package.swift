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
            name: "KaiShared",
            path: "KaiShared"
        ),
        .target(
            name: "KaiLocalAI",
            dependencies: ["KaiShared"],
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
            name: "KaiKnowledge",
            dependencies: ["KaiLocalData"],
            path: "KaiKnowledge"
        ),
        .target(
            name: "KaiAgent",
            dependencies: ["KaiShared"],
            path: "KaiAgent"
        ),
        .target(
            name: "KaiSlack",
            dependencies: ["KaiShared", "KaiKnowledge"],
            path: "KaiSlack"
        ),
        .target(
            name: "KaiNotchCore",
            path: "KaiNotchCore"
        ),
        .target(
            name: "KaiDesk",
            path: "KaiDesk"
        ),
        .executableTarget(
            name: "kai-hook",
            dependencies: ["KaiDesk"],
            path: "KaiHook"
        ),
        .executableTarget(
            name: "KaiOS",
            dependencies: ["KaiShared", "KaiActions", "KaiCapture", "KaiLocalAI", "KaiLocalData", "KaiNotchCore", "KaiKnowledge", "KaiAgent", "KaiSlack", "KaiDesk"],
            path: "Kai OS macOS",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "KaiChecksTests",
            dependencies: ["KaiActions", "KaiCapture", "KaiLocalAI", "KaiLocalData", "KaiNotchCore", "KaiShared", "KaiKnowledge", "KaiAgent", "KaiSlack", "KaiDesk", "kai-hook"],
            path: "Tests/KaiChecksTests"
        )
    ]
)
