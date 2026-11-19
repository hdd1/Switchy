// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switchy",
    platforms: [.macOS(.v15)],
    targets: [
        // Чистая логика без UI: раскладки, маппинг клавиш, конвертация, детектор, буфер набора.
        .target(
            name: "SwitchyCore",
            path: "Sources/SwitchyCore"
        ),
        // Само приложение: строка меню, перехват клавиатуры, окна, настройки.
        .executableTarget(
            name: "Switchy",
            dependencies: ["SwitchyCore"],
            path: "Sources/Switchy"
        ),
        .testTarget(
            name: "SwitchyCoreTests",
            dependencies: ["SwitchyCore"],
            path: "Tests/SwitchyCoreTests"
        ),
    ]
)
