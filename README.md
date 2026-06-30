# ClaudeRemote

iOS 应用，提供原生终端界面来远控运行在同一台 iPad 的 UTM Alpine Linux 虚拟机里的 Claude Code。通过 TrollStore 分发（无需 Apple Developer 账号）。

## 架构

```
+-------------------+          TCP（换行分隔 JSON）        +------------------+
|   iOS 应用        | <----------------------------------- |  Bridge（Alpine）|
|   SwiftTerm TUI   |   bridge 主动外连到 iPad 局域网 IP  |  node-pty + claude|
+-------------------+                                     +------------------+
       |                                                          |
       | SwiftTerm 渲染 xterm-256color                             | claude（agnes API）
       | 发送敲键                                                  | 交互式运行
```

iOS 应用跑 TCP 服务器（`NWListener` 监听 `0.0.0.0:8080`）。Bridge 是 TCP 客户端，连接到 iPad 的局域网 IP，管道转发 PTY I/O。

## 组件

- `bridge/` — Node.js 桥接（运行在 Alpine 虚拟机）
- `ios/` — Swift/SwiftUI iOS 应用（基于 SwiftTerm 的终端）
- `.github/workflows/build-ipa.yml` — 在 GitHub Actions 上构建并打包 IPA

## 快速开始

1. 构建 IPA：推送 `v*` tag 或手动运行 GitHub Actions workflow。下载 `ClaudeRemote.ipa`。
2. 用 TrollStore 在 iPad 上安装。
3. 打开 ClaudeRemote，记下监听地址（如 `192.168.1.42:8080`）。
4. 在 Alpine 虚拟机里运行：
   ```sh
   node bridge/src/bridge.js 192.168.1.42 8080 claude
   ```
5. Claude Code 的 TUI 出现在 iOS 应用里。

## 环境要求

- iPad Pro 2021 / iOS 16.6.1（TrollStore 支持）
- UTM 运行 Alpine Linux 且已安装 `claude`
- iPad 和虚拟机能到达同一局域网
- 无需 Apple 介入（无需开发者账号）

## 开发

### Bridge 测试
```sh
cd bridge && npm test
```

### iOS 测试
```sh
cd ios && swift test
```

### 构建 IPA
触发 GitHub Actions workflow `Build iOS IPA`，或本地：
```sh
cd ios
xcodegen generate --spec project.yml
xcodebuild -project ClaudeRemote.xcodeproj -scheme ClaudeRemote -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO
./scripts/package-ipa.sh build/Build/Products/Release-iphoneos/ClaudeRemote.app ../ClaudeRemote.ipa
```
