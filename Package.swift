// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CountdownWidget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CountdownWidget",
            targets: ["CountdownWidget"]
        ),
        .executable(
            name: "CountdownDesktopWidget",
            targets: ["CountdownDesktopWidget"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CountdownWidget",
            exclude: ["Assets.xcassets"]
        ),
        .executableTarget(
            name: "CountdownDesktopWidget",
            path: "WidgetExtension",
            exclude: [
                "Info.plist",
                "CountdownDesktopWidget.entitlements"
            ]
        ),
        .testTarget(
            name: "CountdownWidgetTests",
            dependencies: ["CountdownWidget"],
            path: "Tests/CountdownWidgetTests"
        )
    ]
)
