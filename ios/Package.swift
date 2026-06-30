// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeRemote",
    platforms: [.iOS(.v16)],
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
            // Info.plist / Assets.xcassets 不是源文件，SPM 不应处理。
            // 这些文件由后续 xcodegen 的 app target 包含编译。
            exclude: ["ClaudeRemoteApp.swift", "Info.plist", "Assets.xcassets"]
        ),
        .testTarget(
            name: "ClaudeRemoteTests",
            dependencies: ["ClaudeRemoteLib"],
            path: "Tests/ClaudeRemoteTests"
        ),
    ]
)
