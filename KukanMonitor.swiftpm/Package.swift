// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "KukanMonitor",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "KukanMonitor",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.kukanmonitor",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .camera(purposeString: "AR表示でカメラ映像を背景に映します。映像は保存も送信もしません。")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
