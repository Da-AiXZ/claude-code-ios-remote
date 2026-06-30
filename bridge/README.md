# Claude Bridge

运行在 Alpine Linux 虚拟机里（UTM on iPad）。用 PTY spawn `claude`，把 I/O 流式转发到 iOS 应用（TCP）。

## 安装（Alpine）

```sh
apk add nodejs npm python3 make g++   # node-pty 需要 C++ 工具链
cd /root/bridge
npm install
```

## 配置 Claude Code（agnes 服务商）

确保 `~/.claude.json` 或环境变量指向你的 agnes API endpoint，例如：

```sh
export ANTHROPIC_BASE_URL="https://your-agnes-endpoint/v1"
export ANTHROPIC_API_KEY="sk-..."
```

启动 bridge 前先在虚拟机里确认 `claude` 能正常工作。

## 运行

1. 在 iPad 上打开 ClaudeRemote。记下显示的地址（如 `192.168.1.42:8080`）。
2. 在 Alpine 里：

```sh
node src/bridge.js 192.168.1.42 8080 claude
```

3. Claude Code 的 TUI 应该出现在 iOS 应用里。

## 排错

- **连不上**：确认两台设备在同一 WiFi。若路由器阻断 hairpin NAT，在另一台局域网主机上跑 TCP 中继（如 `socat TCP-LISTEN:8080,fork TCP:<ipad-ip>:8080`），把 bridge 指向中继。
- **乱码**：确认 `TERM=xterm-256color`（node-pty 自动设置）。
- **找不到 claude**：`export CLAUDE_PATH=/usr/local/bin/claude` 或作为第 4 个参数传入。

## 安装 iOS 应用（TrollStore）

1. 从 GitHub Actions 的 artifacts（或 Releases）下载 `ClaudeRemote.ipa`。
2. 在 iPad 上打开 TrollStore（支持 iOS 16.6.1）。
3. 点 **+**，选择 `.ipa` 文件。
4. 安装后从主屏幕启动 **ClaudeRemote**。
5. 弹窗时授予本地网络权限。

## 自己构建 IPA

推送 `v1.0.0` tag 触发 GitHub Actions 构建，或在 Actions 标签页手动运行 workflow。下载 artifact，用 TrollStore 安装。
