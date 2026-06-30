// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeRemote",
    // iOS 16 用于 app 打包；macOS 13 用于在 macOS runner 上跑 swift test（SwiftTerm 要求 macOS 13+）。
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ClaudeRemoteLib", targets: ["ClaudeRemoteLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "ClaudeRemoteLib",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "ClaudeRemote",
            // ClaudeRemoteApp.swift 带 @main，SPM library target 不允许；
            // Info.plist 不是源文件，SPM 不应处理。
            // Views/ 是 UIKit/SwiftUI iOS-only 代码（UIViewRepresentable 等），
            // macOS runner 跑 swift test 时无法编译；这些由 xcodegen 的 iOS app target 编译。
            // 核心逻辑（Message/LocalNetwork/TerminalServer/TerminalSession）跨平台，可被 macOS 测试。
            exclude: ["ClaudeRemoteApp.swift", "Info.plist", "Views"]
        ),
        .testTarget(
            name: "ClaudeRemoteTests",
            dependencies: ["ClaudeRemoteLib"],
            path: "Tests/ClaudeRemoteTests"
        ),
    ]
)
