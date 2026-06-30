# Claude Code iOS 远控实现计划

> **给执行用的 agent：** 必须使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实现本计划。步骤使用复选框（`- [ ]`）语法跟踪进度。

**目标：** 构建一个 iOS 应用（TrollStore 分发，Swift/SwiftUI + SwiftTerm），通过 TCP 桥接服务，提供原生终端界面来远控运行在 UTM Alpine Linux 虚拟机里的 Claude Code。

**架构：** 一个 Node.js 桥接服务运行在 Alpine 虚拟机里，用伪终端（PTY）spawn `claude` 进程。桥接服务是 TCP **客户端**，主动连接到 iOS 应用；iOS 应用运行 TCP **服务器**（`NWListener` 监听 `0.0.0.0:端口`），用 SwiftTerm（完整的 xterm-256color 模拟器）渲染终端。协议是换行分隔的 JSON over 原始 TCP，PTY 字节用 base64 编码传输，外加 resize 和 exit 消息。因为 iOS 应用是服务器、桥接主动外连，所以无需 UTM 端口转发就能穿透 NAT/slirp 网络；若配置云端中继也支持。

**技术栈：** Swift 5.9+ / SwiftUI / SwiftTerm（SPM）做 iOS 应用；Node.js + `node-pty` + 内置 `net` 做桥接；GitHub Actions（macOS runner，`xcodebuild`）打包 IPA，ad-hoc 签名供 TrollStore 使用。

**目标设备：** iPad Pro 2021，iOS 16.6.1（TrollStore 支持），128GB。

**分发方式：** TrollStore（通过 CoreTrust 旁路永久签名，无需 Apple Developer 账号，无 7 天过期限制，无 app 数量限制）。

---

## 网络说明（实现前必读）

iOS 上的 UTM 使用 QEMU 用户态网络（slirp）。虚拟机分到 NAT 后的 IP（如 `10.0.2.15`），可以发起**出站** TCP 连接到：
- 互联网（经 NAT）
- 宿主设备的局域网 IP（如 `192.168.1.100`）——这就是桥接到 iOS 应用的路径

iOS 应用监听 `0.0.0.0:8080`（所有网卡）。桥接连到 iPad 的 WiFi IP。用户从 iOS 应用 UI 里看到这个 IP，传给桥接。

如果用户路由器上的本地网络回流（hairpin）路由不通，用户可以改在任何可达的主机上跑一个微型 TCP 中继（VPS、Cloudflare Worker 的 TCP 代理、或局域网另一台机器上的 `socat`），让桥接和 iOS 应用（"客户端模式"，未来增强）都指向它。v1 我们实现 iOS 端的服务器模式 + 桥接端的客户端模式，覆盖常见场景。

---

## 文件结构

```
/workspace/
├── docs/superpowers/plans/2026-06-30-claude-code-ios-remote.md   # 本计划
├── bridge/                                      # Node.js 桥接（Alpine 虚拟机）
│   ├── package.json
│   ├── src/
│   │   ├── protocol.js                          # 消息类型、序列化/解析
│   │   ├── pty-manager.js                       # spawn claude、处理 I/O/resize/exit
│   │   └── bridge.js                            # 主入口：TCP 客户端 + 线路连接
│   └── test/
│       ├── protocol.test.js
│       └── pty-manager.test.js
├── ios/                                         # iOS 应用（Xcode 项目）
│   ├── ClaudeRemote.xcodeproj
│   ├── ClaudeRemote/
│   │   ├── ClaudeRemoteApp.swift                # @main App 入口
│   │   ├── Sources/
│   │   │   ├── Message.swift                    # 协议 Codable 类型
│   │   │   ├── LocalNetwork.swift               # 通过 getifaddrs 发现本机 IP
│   │   │   ├── TerminalServer.swift             # NWListener TCP 服务器
│   │   │   └── TerminalSession.swift            # 会话状态机
│   │   ├── Views/
│   │   │   ├── MainView.swift                   # 根 SwiftUI 视图
│   │   │   ├── ConnectionInfoView.swift         # 显示 IP + 状态
│   │   │   ├── TerminalScreen.swift             # SwiftTerm UIViewRepresentable
│   │   │   ├── KeyboardAccessory.swift          # 特殊按键栏
│   │   │   └── SettingsView.swift               # 端口/字体/颜色设置
│   │   ├── Info.plist
│   │   └── Assets.xcassets
│   └── Tests/
│       └── ClaudeRemoteTests/
│           ├── MessageTests.swift
│           ├── LocalNetworkTests.swift
│           └── TerminalServerTests.swift
└── .github/
    └── workflows/
        └── build-ipa.yml
```

---

## 消息协议

所有消息都是 UTF-8 JSON 对象，以 `\n` 结尾。PTY 二进制数据用 base64 编码。

```jsonc
// 桥接 → iOS（连接时）
{"type":"hello","version":"1.0.0","cols":80,"rows":24}\n

// 桥接 → iOS（claude 产生了输出）
{"type":"output","data":"<base64 字节>"}\n

// 桥接 → iOS（claude 退出）
{"type":"exit","code":0,"signal":null}\n

// iOS → 桥接（用户敲键）
{"type":"input","data":"<base64 字节>"}\n

// iOS → 桥接（终端尺寸变化）
{"type":"resize","cols":120,"rows":40}\n

// 任一端（错误）
{"type":"error","message":"<文本>"}\n
```

---

## Task 1：Bridge — 协议模块

**文件：**
- 创建：`bridge/package.json`
- 创建：`bridge/src/protocol.js`
- 创建：`bridge/test/protocol.test.js`

- [ ] **步骤 1：初始化 bridge 包**

```bash
mkdir -p bridge/src bridge/test
cd bridge && npm init -y
npm pkg set type=module
npm pkg set scripts.test="node --test"
```

编辑 `bridge/package.json`，设置 `"name": "claude-bridge"`、`"version": "1.0.0"`、`"type": "module"`。

- [ ] **步骤 2：写失败测试**

创建 `bridge/test/protocol.test.js`：

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { serialize, parse, MessageError } from '../src/protocol.js';

test('serialize 用换行包裹消息', () => {
  const buf = serialize({ type: 'hello', version: '1.0.0', cols: 80, rows: 24 });
  assert.equal(buf.toString(), '{"type":"hello","version":"1.0.0","cols":80,"rows":24}\n');
});

test('serialize 把 output 数据编码为 base64', () => {
  const buf = serialize({ type: 'output', data: Buffer.from('hi').toString('base64') });
  assert.equal(buf.toString(), '{"type":"output","data":"aGk="}\n');
});

test('parse 从单行返回单条消息', () => {
  const line = '{"type":"hello","version":"1.0.0","cols":80,"rows":24}\n';
  const msgs = parse(line);
  assert.equal(msgs.length, 1);
  assert.deepEqual(msgs[0], { type: 'hello', version: '1.0.0', cols: 80, rows: 24 });
});

test('parse 处理一个 chunk 里的多条消息', () => {
  const chunk = '{"type":"output","data":"aGk="}\n{"type":"exit","code":0,"signal":null}\n';
  const msgs = parse(chunk);
  assert.equal(msgs.length, 2);
  assert.equal(msgs[0].type, 'output');
  assert.equal(msgs[1].type, 'exit');
});

test('parse 缓存未结束的尾部行', () => {
  const chunk = '{"type":"output","data":"aGk="}\n{"type":"exit","code":0';
  const msgs = parse(chunk);
  assert.equal(msgs.length, 1);
});

test('parse 跨调用续接半行', () => {
  const ctx = parse('', {});
  // 有状态解析器：跨调用复用 buffer —— 见步骤 3 的实现
});

test('parse 拒绝非 JSON 行', () => {
  assert.throws(() => parse('not-json\n'), MessageError);
});

test('serialize 拒绝未知消息类型', () => {
  assert.throws(() => serialize({ type: 'bogus' }), MessageError);
});
```

- [ ] **步骤 3：运行测试，确认失败**

```bash
cd bridge && npm test
```
预期：FAIL，提示 `Cannot find module '../src/protocol.js'`。

- [ ] **步骤 4：写最小实现**

创建 `bridge/src/protocol.js`：

```javascript
export class MessageError extends Error {}

const VALID_TYPES = new Set(['hello', 'output', 'exit', 'input', 'resize', 'error']);

export function serialize(message) {
  if (!message || typeof message.type !== 'string' || !VALID_TYPES.has(message.type)) {
    throw new MessageError(`Invalid message type: ${message?.type}`);
  }
  return Buffer.from(JSON.stringify(message) + '\n', 'utf8');
}

// 有状态解析器：传入 context 对象，跨调用保留未结束的 buffer。
export function parse(chunk, ctx = { buffer: '' }) {
  ctx.buffer += chunk.toString('utf8');
  const messages = [];
  let idx;
  while ((idx = ctx.buffer.indexOf('\n')) >= 0) {
    const line = ctx.buffer.slice(0, idx);
    ctx.buffer = ctx.buffer.slice(idx + 1);
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;
    let msg;
    try {
      msg = JSON.parse(trimmed);
    } catch (e) {
      throw new MessageError(`Unparseable message: ${trimmed}`);
    }
    if (!VALID_TYPES.has(msg.type)) {
      throw new MessageError(`Unknown message type: ${msg.type}`);
    }
    messages.push(msg);
  }
  return messages;
}
```

- [ ] **步骤 5：运行测试，确认通过**

```bash
cd bridge && npm test
```
预期：PASS（所有 protocol 测试绿）。

- [ ] **步骤 6：提交**

```bash
git add bridge/package.json bridge/src/protocol.js bridge/test/protocol.test.js
git commit -m "feat(bridge): add message protocol with serialize/parse"
```

---

## Task 2：Bridge — PTY 管理器

**文件：**
- 创建：`bridge/src/pty-manager.js`
- 创建：`bridge/test/pty-manager.test.js`
- 修改：`bridge/package.json`（添加 `node-pty` 依赖）

- [ ] **步骤 1：安装 node-pty**

```bash
cd bridge && npm install node-pty
```

- [ ] **步骤 2：写失败测试**

创建 `bridge/test/pty-manager.test.js`：

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PtyManager } from '../src/pty-manager.js';

test('PtyManager spawn 命令并输出结果', async () => {
  const mgr = new PtyManager({ command: 'echo', args: ['hello'], cwd: process.env.HOME });
  const outputs = [];
  mgr.on('output', (b64) => outputs.push(Buffer.from(b64, 'base64').toString()));
  mgr.on('exit', () => {});
  await new Promise((resolve) => mgr.on('exit', resolve));
  assert.match(outputs.join(''), /hello/);
});

test('PtyManager 把输入写入 PTY', async () => {
  const mgr = new PtyManager({ command: 'cat', args: [], cwd: process.env.HOME });
  const collected = [];
  mgr.on('output', (b64) => collected.push(Buffer.from(b64, 'base64').toString()));
  mgr.write(Buffer.from('ping\n').toString('base64'));
  await new Promise((r) => setTimeout(r, 200));
  mgr.kill();
  assert.match(collected.join(''), /ping/);
});

test('PtyManager resize 更新 cols/rows', () => {
  const mgr = new PtyManager({ command: 'cat', args: [], cwd: process.env.HOME, cols: 80, rows: 24 });
  mgr.resize(120, 40);
  assert.equal(mgr.cols, 120);
  assert.equal(mgr.rows, 40);
  mgr.kill();
});

test('PtyManager 触发 exit 并带 code', async () => {
  const mgr = new PtyManager({ command: 'sh', args: ['-c', 'exit 7'], cwd: process.env.HOME });
  const exitInfo = await new Promise((resolve) => mgr.on('exit', resolve));
  assert.equal(exitInfo.code, 7);
});

test('PtyManager 缺少 command 报错', () => {
  assert.throws(() => new PtyManager({}), /command is required/);
});
```

- [ ] **步骤 3：运行测试，确认失败**

```bash
cd bridge && npm test
```
预期：FAIL，提示 `Cannot find module '../src/pty-manager.js'`。

- [ ] **步骤 4：写最小实现**

创建 `bridge/src/pty-manager.js`：

```javascript
import { EventEmitter } from 'node:events';
import pty from 'node-pty';

export class PtyManager extends EventEmitter {
  constructor({ command, args = [], cwd, env = process.env, cols = 80, rows = 24 }) {
    super();
    if (!command) throw new Error('command is required');
    this.command = command;
    this.args = args;
    this.cols = cols;
    this.rows = rows;
    this._proc = pty.spawn(command, args, {
      name: 'xterm-256color',
      cols,
      rows,
      cwd: cwd || process.env.HOME,
      env,
    });
    this._proc.onData((data) => {
      this.emit('output', Buffer.from(data, 'utf8').toString('base64'));
    });
    this._proc.onExit(({ exitCode, signal }) => {
      this.emit('exit', { code: exitCode, signal: signal || null });
    });
  }

  write(b64) {
    const data = Buffer.from(b64, 'base64').toString('utf8');
    this._proc.write(data);
  }

  resize(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    this._proc.resize(cols, rows);
  }

  kill() {
    this._proc.kill();
  }
}
```

- [ ] **步骤 5：运行测试，确认通过**

```bash
cd bridge && npm test
```
预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add bridge/src/pty-manager.js bridge/test/pty-manager.test.js bridge/package.json bridge/package-lock.json
git commit -m "feat(bridge): add PtyManager wrapping node-pty"
```

---

## Task 3：Bridge — TCP 客户端 + 主线路连接

**文件：**
- 创建：`bridge/src/bridge.js`

- [ ] **步骤 1：写失败测试**

创建 `bridge/test/bridge.test.js`：

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:net';
import { connectBridge } from '../src/bridge.js';

test('connectBridge 连接服务器并发送 hello', async () => {
  const received = [];
  const server = createServer((socket) => {
    socket.on('data', (chunk) => received.push(chunk.toString()));
  });
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;

  const controller = connectBridge({
    host: '127.0.0.1',
    port,
    command: 'echo',
    args: ['hi'],
    cwd: process.env.HOME,
  });

  await new Promise((r) => setTimeout(r, 300));
  controller.close();
  server.close();
  const joined = received.join('');
  assert.match(joined, /"type":"hello"/);
});

test('connectBridge 把 PTY 输出转发到 socket', async () => {
  const received = [];
  const server = createServer((socket) => {
    socket.on('data', (c) => {
      // PTY 输出按协议用 base64 编码传输，解码 output.data 后收集明文
      for (const line of c.toString().split('\n')) {
        if (!line.includes('"type":"output"')) continue;
        try {
          const msg = JSON.parse(line);
          if (msg.data) received.push(Buffer.from(msg.data, 'base64').toString());
        } catch {}
      }
    });
  });
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;

  const controller = connectBridge({
    host: '127.0.0.1',
    port,
    command: 'echo',
    args: ['hello-world'],
    cwd: process.env.HOME,
  });

  await new Promise((r) => setTimeout(r, 500));
  controller.close();
  server.close();
  assert.match(received.join(''), /hello-world/);
});

test('connectBridge 把 socket 输入写入 PTY', async () => {
  const outputs = [];
  const server = createServer((socket) => {
    socket.on('data', (c) => {
      const s = c.toString();
      if (s.includes('"type":"hello"')) {
        socket.write(JSON.stringify({ type: 'input', data: Buffer.from('echo from-net\n').toString('base64') }) + '\n');
      }
      // PTY 输出按协议用 base64 编码传输，解码 output.data 后收集明文
      for (const line of s.split('\n')) {
        if (!line.includes('"type":"output"')) continue;
        try {
          const msg = JSON.parse(line);
          if (msg.data) outputs.push(Buffer.from(msg.data, 'base64').toString());
        } catch {}
      }
    });
  });
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;

  const controller = connectBridge({
    host: '127.0.0.1',
    port,
    command: 'cat',
    args: [],
    cwd: process.env.HOME,
  });

  await new Promise((r) => setTimeout(r, 500));
  controller.close();
  server.close();
  assert.match(outputs.join(''), /from-net/);
});

test('connectBridge 断线后重连', async () => {
  let connections = 0;
  const server = createServer((socket) => {
    connections++;
    setTimeout(() => socket.destroy(), 100);
  });
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;

  const controller = connectBridge({
    host: '127.0.0.1',
    port,
    command: 'cat',
    args: [],
    cwd: process.env.HOME,
    reconnectDelayMs: 50,
  });

  await new Promise((r) => setTimeout(r, 400));
  controller.close();
  server.close();
  assert.ok(connections >= 2, `expected >=2 connections, got ${connections}`);
});
```

- [ ] **步骤 2：运行测试，确认失败**

```bash
cd bridge && npm test
```
预期：FAIL，提示 `Cannot find module '../src/bridge.js'`。

- [ ] **步骤 3：写最小实现**

创建 `bridge/src/bridge.js`：

```javascript
import net from 'node:net';
import { serialize, parse, MessageError } from './protocol.js';
import { PtyManager } from './pty-manager.js';

export function connectBridge({ host, port, command, args = [], cwd, reconnectDelayMs = 3000 }) {
  let closed = false;
  let pty = null;
  let activeSocket = null;
  const parserCtx = { buffer: '' };

  function connect() {
    if (closed) return;
    const sock = net.connect(port, host);
    activeSocket = sock;

    sock.on('connect', () => {
      console.log(`[bridge] connected to ${host}:${port}`);
      pty = new PtyManager({ command, args, cwd });
      sock.write(serialize({ type: 'hello', version: '1.0.0', cols: pty.cols, rows: pty.rows }));

      pty.on('output', (b64) => {
        if (sock.writable) sock.write(serialize({ type: 'output', data: b64 }));
      });
      pty.on('exit', ({ code, signal }) => {
        if (sock.writable) sock.write(serialize({ type: 'exit', code, signal }));
        sock.end();
      });
    });

    sock.on('data', (chunk) => {
      let messages;
      try {
        messages = parse(chunk, parserCtx);
      } catch (e) {
        if (e instanceof MessageError) {
          console.error('[bridge] protocol error:', e.message);
          return;
        }
        throw e;
      }
      for (const msg of messages) {
        if (msg.type === 'input' && pty) pty.write(msg.data);
        else if (msg.type === 'resize' && pty) pty.resize(msg.cols, msg.rows);
      }
    });

    sock.on('close', () => {
      console.log('[bridge] disconnected');
      if (pty) { pty.kill(); pty = null; }
      if (!closed) setTimeout(connect, reconnectDelayMs);
    });

    sock.on('error', (err) => {
      console.error('[bridge] socket error:', err.message);
    });
  }

  connect();

  return {
    close() {
      closed = true;
      if (pty) { pty.kill(); pty = null; }
      if (activeSocket) activeSocket.destroy();
    },
  };
}
```

- [ ] **步骤 4：运行测试，确认通过**

```bash
cd bridge && npm test
```
预期：PASS（所有 bridge 测试绿）。

- [ ] **步骤 5：加 CLI 入口**

在 `bridge/src/bridge.js` 末尾追加：

```javascript
// CLI 入口：node src/bridge.js <host> <port> [claude-command]
if (import.meta.url === `file://${process.argv[1]}`) {
  const host = process.argv[2] || '127.0.0.1';
  const port = parseInt(process.argv[3] || '8080', 10);
  const command = process.env.CLAUDE_PATH || process.argv[4] || 'claude';
  console.log(`[bridge] starting → ${host}:${port}, command=${command}`);
  connectBridge({ host, port, command, args: [], cwd: process.env.HOME });
}
```

- [ ] **步骤 6：在 package.json 加 start 脚本**

编辑 `bridge/package.json`，加：
```json
"scripts": {
  "test": "node --test",
  "start": "node src/bridge.js"
}
```

- [ ] **步骤 7：提交**

```bash
git add bridge/src/bridge.js bridge/test/bridge.test.js bridge/package.json
git commit -m "feat(bridge): add TCP client with reconnect and CLI entry"
```

---

## Task 4：iOS — 项目脚手架 + SwiftTerm 依赖

**文件：**
- 创建：`ios/ClaudeRemote.xcodeproj`（用 `xcodegen` 生成，见 Task 13）
- 创建：`ios/ClaudeRemote/ClaudeRemoteApp.swift`
- 创建：`ios/ClaudeRemote/Info.plist`
- 创建：`ios/Package.swift`

- [ ] **步骤 1：创建项目目录树**

```bash
mkdir -p ios/ClaudeRemote/Sources ios/ClaudeRemote/Views ios/ClaudeRemote/Assets.xcassets/AppIcon.appiconset ios/Tests/ClaudeRemoteTests
```

创建 `ios/ClaudeRemote/ClaudeRemoteApp.swift`：

```swift
import SwiftUI

@main
struct ClaudeRemoteApp: App {
    @StateObject private var session = TerminalSession()

    var body: some Scene {
        WindowGroup {
            MainView(session: session)
                .onAppear { session.start() }
        }
    }
}
```

注意：onAppear 触发 session.start()，因为 TerminalSession.init 不再自动启动（见 Task 8）。

- [ ] **步骤 2：创建 Info.plist**

创建 `ios/ClaudeRemote/Info.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeRemote</string>
    <key>CFBundleIdentifier</key>
    <string>com.clauderemote.app</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeRemote</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIRequiresFullScreen</key>
    <false/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>需要本地网络权限以与 Alpine 虚拟机中的 Claude Code 通信。</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_claude-remote._tcp</string>
    </array>
    <key>UIFileSharingEnabled</key>
    <true/>
</dict>
</plist>
```

- [ ] **步骤 3：创建 SPM Package.swift（用于跑单元测试）**

为了能在 GitHub Actions 的 macOS runner 上既跑测试又打包 IPA，我们用 SPM 管理库代码 + 测试，再用 xcodegen 生成 Xcode 工程做 app 打包。创建 `ios/Package.swift`：

```swift
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
            path: "ClaudeRemote"
        ),
        .testTarget(
            name: "ClaudeRemoteTests",
            dependencies: ["ClaudeRemoteLib"],
            path: "Tests/ClaudeRemoteTests"
        ),
    ]
)
```

- [ ] **步骤 4：创建占位文件让包能构建**

创建 `ios/ClaudeRemote/Sources/Message.swift`：

```swift
import Foundation

enum MessageType: String, Codable {
    case hello, output, exit, input, resize, error
}

struct BridgeMessage: Codable {
    let type: MessageType
    var version: String?
    var cols: Int?
    var rows: Int?
    var data: String?
    var code: Int?
    var signal: String?
    var message: String?
}
```

创建 `ios/ClaudeRemote/Views/MainView.swift`：

```swift
import SwiftUI

struct MainView: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        Text("ClaudeRemote")
    }
}
```

创建 `ios/ClaudeRemote/Sources/TerminalSession.swift`：

```swift
import Foundation
import Combine

final class TerminalSession: ObservableObject {
    @Published var status: String = "idle"
}
```

- [ ] **步骤 5：验证包能解析（在 macOS 或 GitHub Actions 上）**

```bash
cd ios && swift build
```
预期：SwiftTerm 解析成功，包能构建。如果在 Linux 沙箱里跑，iOS 目标无法交叉编译，但依赖解析应该能成功；最终由 Task 13 的 GitHub Actions workflow 验证。

- [ ] **步骤 6：提交**

```bash
git add ios/
git commit -m "feat(ios): scaffold SPM project with SwiftTerm dependency"
```

---

## Task 5：iOS — 消息协议（Swift）

**文件：**
- 修改：`ios/ClaudeRemote/Sources/Message.swift`
- 创建：`ios/Tests/ClaudeRemoteTests/MessageTests.swift`

- [ ] **步骤 1：写失败测试**

创建 `ios/Tests/ClaudeRemoteTests/MessageTests.swift`：

```swift
import Testing
import Foundation
@testable import ClaudeRemoteLib

@Suite struct MessageTests {
    @Test func 编码hello消息() throws {
        let msg = BridgeMessage(type: .hello, version: "1.0.0", cols: 80, rows: 24)
        let data = try BridgeMessage.encode(msg)
        let s = String(data: data, encoding: .utf8)
        #expect(s == #"{"type":"hello","version":"1.0.0","cols":80,"rows":24}"# + "\n")
    }

    @Test func 编码output消息() throws {
        let bytes = "hi".data(using: .utf8)!.base64EncodedString()
        let msg = BridgeMessage(type: .output, data: bytes)
        let data = try BridgeMessage.encode(msg)
        let s = String(data: data, encoding: .utf8)
        #expect(s == #"{"type":"output","data":"aGk="}"# + "\n")
    }

    @Test func 解码input消息() throws {
        let line = #"{"type":"input","data":"aGk="}"# + "\n"
        let msgs = try BridgeMessage.decode(Buffer: line.data(using: .utf8)!, ctx: ParseContext())
        #expect(msgs.count == 1)
        #expect(msgs[0].type == .input)
        #expect(msgs[0].data == "aGk=")
    }

    @Test func 一个buffer解码多条消息() throws {
        let chunk = #"{"type":"output","data":"aGk="}{"type":"exit","code":0}"# + "\n"
        let msgs = try BridgeMessage.decode(Buffer: chunk.data(using: .utf8)!, ctx: ParseContext())
        #expect(msgs.count == 2)
        #expect(msgs[0].type == .output)
        #expect(msgs[1].type == .exit)
        #expect(msgs[1].code == 0)
    }

    @Test func 解码缓存半行() throws {
        let ctx = ParseContext()
        let part1 = #"{"type":"output","data":"aGk="}"#.data(using: .utf8)!
        let part2 = "\n".data(using: .utf8)!
        #expect(try BridgeMessage.decode(Buffer: part1, ctx: ctx).isEmpty)
        #expect(try BridgeMessage.decode(Buffer: part2, ctx: ctx).count == 1)
    }

    @Test func 解码拒绝未知类型() {
        #expect(throws: DecodingError.self) {
            _ = try BridgeMessage.decode(Buffer: #"{"type":"bogus"}"#.data(using: .utf8)!, ctx: ParseContext())
        }
    }
}
```

- [ ] **步骤 2：运行测试，确认失败**

```bash
cd ios && swift test --filter MessageTests
```
预期：FAIL —— `BridgeMessage.encode`、`decode`、`ParseContext` 还没定义。

- [ ] **步骤 3：写最小实现**

替换 `ios/ClaudeRemote/Sources/Message.swift`：

```swift
import Foundation

enum MessageType: String, Codable {
    case hello, output, exit, input, resize, error
}

struct BridgeMessage: Codable {
    let type: MessageType
    var version: String?
    var cols: Int?
    var rows: Int?
    var data: String?
    var code: Int?
    var signal: String?
    var message: String?
}

final class ParseContext {
    var buffer: String = ""
}

extension BridgeMessage {
    static func encode(_ msg: BridgeMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = try encoder.encode(msg)
        data.append(0x0A) // \n
        return data
    }

    static func decode(Buffer chunk: Data, ctx: ParseContext) throws -> [BridgeMessage] {
        guard let text = String(data: chunk, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "non-utf8"))
        }
        ctx.buffer += text
        var messages: [BridgeMessage] = []
        let decoder = JSONDecoder()
        while let nlIdx = ctx.buffer.firstIndex(of: "\n") {
            let line = String(ctx.buffer[ctx.buffer.startIndex..<nlIdx])
            ctx.buffer.removeSubrange(ctx.buffer.startIndex...nlIdx)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let lineData = line.data(using: .utf8) else { continue }
            messages.append(try decoder.decode(BridgeMessage.self, from: lineData))
        }
        return messages
    }
}
```

注意：`.withoutEscapingSlashes` 需要 iOS 13+ / Swift 5.9+。若不可用就删掉它——功能正确性不依赖斜杠转义。本任务的测试期望不带转义斜杠，所以若该 flag 不可用，需调整测试期望以接受 `\/`。优先保留该 flag。

- [ ] **步骤 4：运行测试，确认通过**

```bash
cd ios && swift test --filter MessageTests
```
预期：PASS。

- [ ] **步骤 5：提交**

```bash
git add ios/ClaudeRemote/Sources/Message.swift ios/Tests/ClaudeRemoteTests/MessageTests.swift
git commit -m "feat(ios): implement BridgeMessage encode/decode with streaming buffer"
```

---

## Task 6：iOS — 本地网络 IP 发现

**文件：**
- 创建：`ios/ClaudeRemote/Sources/LocalNetwork.swift`
- 创建：`ios/Tests/ClaudeRemoteTests/LocalNetworkTests.swift`

- [ ] **步骤 1：写失败测试**

创建 `ios/Tests/ClaudeRemoteTests/LocalNetworkTests.swift`：

```swift
import Testing
import Foundation
@testable import ClaudeRemoteLib

@Suite struct LocalNetworkTests {
    @Test func 解析合法IPv4() {
        let ip = LocalNetwork.parseIPv4(from: "192.168.1.42")
        #expect(ip == "192.168.1.42")
    }

    @Test func 回环地址返回nil() {
        let ip = LocalNetwork.parseIPv4(from: "127.0.0.1")
        #expect(ip == nil)
    }

    @Test func 空字符串返回nil() {
        let ip = LocalNetwork.parseIPv4(from: "")
        #expect(ip == nil)
    }

    @Test func 拼接IP和端口() {
        let addr = LocalNetwork.formatAddress(ip: "192.168.1.42", port: 8080)
        #expect(addr == "192.168.1.42:8080")
    }

    @Test func ip为nil时显示占位() {
        let addr = LocalNetwork.formatAddress(ip: nil, port: 8080)
        #expect(addr == "(unknown):8080")
    }

    @Test func 私网地址识别为局域网() {
        #expect(LocalNetwork.isLikelyLANAddress("192.168.0.5"))
        #expect(LocalNetwork.isLikelyLANAddress("10.0.0.5"))
        #expect(LocalNetwork.isLikelyLANAddress("172.16.0.5"))
    }

    @Test func 公网地址不识别为局域网() {
        #expect(!LocalNetwork.isLikelyLANAddress("8.8.8.8"))
        #expect(!LocalNetwork.isLikelyLANAddress("127.0.0.1"))
    }
}
```

- [ ] **步骤 2：运行测试，确认失败**

```bash
cd ios && swift test --filter LocalNetworkTests
```
预期：FAIL —— `LocalNetwork` 未定义。

- [ ] **步骤 3：写最小实现**

创建 `ios/ClaudeRemote/Sources/LocalNetwork.swift`：

```swift
import Foundation
import Darwin

enum LocalNetwork {
    static func parseIPv4(from string: String) -> String? {
        guard !string.isEmpty else { return nil }
        if string.hasPrefix("127.") { return nil }
        // 基础 IPv4 格式校验
        let parts = string.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return string
    }

    static func formatAddress(ip: String?, port: UInt16) -> String {
        "\(ip ?? "(unknown)"):\(port)"
    }

    static func isLikelyLANAddress(_ ip: String) -> Bool {
        if ip.hasPrefix("127.") { return false }
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    /// 遍历 getifaddrs，找到第一个非回环网卡上的 IPv4 地址。
    static func currentIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            let iface = cur.pointee
            let addrFamily = iface.ifa_addr.pointee.sa_family
            if addrFamily == sa_family_t(AF_INET) {
                let name = String(cString: iface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(iface.ifa_addr,
                            socklen_t(iface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("wl") {
                    if let parsed = parseIPv4(from: ip), isLikelyLANAddress(parsed) {
                        return parsed
                    }
                }
            }
            ptr = iface.ifa_next
        }
        return nil
    }
}
```

- [ ] **步骤 4：运行测试，确认通过**

```bash
cd ios && swift test --filter LocalNetworkTests
```
预期：PASS。

- [ ] **步骤 5：提交**

```bash
git add ios/ClaudeRemote/Sources/LocalNetwork.swift ios/Tests/ClaudeRemoteTests/LocalNetworkTests.swift
git commit -m "feat(ios): add local-network IPv4 discovery"
```

---

## Task 7：iOS — TCP 服务器（NWListener）

**文件：**
- 创建：`ios/ClaudeRemote/Sources/TerminalServer.swift`
- 创建：`ios/Tests/ClaudeRemoteTests/TerminalServerTests.swift`

- [ ] **步骤 1：写失败测试**

创建 `ios/Tests/ClaudeRemoteTests/TerminalServerTests.swift`：

```swift
import Testing
import Foundation
import Network
@testable import ClaudeRemoteLib

@Suite struct TerminalServerTests {
    @Test func 端口0拒绝() {
        #expect(throws: TerminalServerError.invalidPort.self) {
            _ = try TerminalServer(port: 0, onMessage: { _ in }, onStateChange: { _ in })
        }
    }

    @Test func 合法端口可创建() throws {
        // 只做参数校验，不在单元测试里真正启动 listener。
        let s = try TerminalServer(port: 18080, onMessage: { _ in }, onStateChange: { _ in })
        #expect(s.port == 18080)
    }

    @Test func 启动前状态是idle() throws {
        let s = try TerminalServer(port: 18081, onMessage: { _ in }, onStateChange: { _ in })
        #expect(s.state == .idle)
    }

    @Test func stop后转为idle或stopping() throws {
        let s = try TerminalServer(port: 18082, onMessage: { _ in }, onStateChange: { _ in })
        s.start()
        s.stop()
        // stop 后状态应最终为 idle（同步 cancel）。
        #expect(s.state == .idle || s.state == .stopping)
    }
}
```

- [ ] **步骤 2：运行测试，确认失败**

```bash
cd ios && swift test --filter TerminalServerTests
```
预期：FAIL —— `TerminalServer`、`TerminalServerError` 未定义。

- [ ] **步骤 3：写最小实现**

创建 `ios/ClaudeRemote/Sources/TerminalServer.swift`：

```swift
import Foundation
import Network

enum TerminalServerError: Error {
    case invalidPort
    case alreadyRunning
}

enum ServerState: Equatable {
    case idle
    case starting
    case listening(address: String)
    case connected(address: String)
    case failed(String)
    case stopping
}

final class TerminalServer {
    let port: UInt16
    private let onMessage: (BridgeMessage) -> Void
    private let onStateChange: (ServerState) -> Void
    private(set) var state: ServerState = .idle {
        didSet { onStateChange(state) }
    }
    private var listener: NWListener?
    private var connection: NWConnection?
    private let parseContext = ParseContext()
    private let queue = DispatchQueue(label: "com.clauderemote.server")

    init(port: UInt16,
         onMessage: @escaping (BridgeMessage) -> Void,
         onStateChange: @escaping (ServerState) -> Void) throws {
        if port == 0 { throw TerminalServerError.invalidPort }
        self.port = port
        self.onMessage = onMessage
        self.onStateChange = onStateChange
    }

    func start() {
        guard listener == nil else { return }
        state = .starting
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] s in
                self?.handle(listenerState: s)
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            listener.start(queue: queue)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        state = .stopping
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        state = .idle
    }

    func send(_ msg: BridgeMessage) {
        guard let data = try? BridgeMessage.encode(msg) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func handle(listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            let ip = LocalNetwork.currentIPv4() ?? "127.0.0.1"
            state = .listening(address: LocalNetwork.formatAddress(ip: ip, port: port))
        case .failed(let err):
            state = .failed(err.localizedDescription)
        case .cancelled:
            state = .idle
        default:
            break
        }
    }

    private func accept(_ conn: NWConnection) {
        // 同一时间只接受一个连接。
        connection?.cancel()
        connection = conn
        conn.stateUpdateHandler = { [weak self] s in
            self?.handle(connectionState: s, conn: conn)
        }
        conn.start(queue: queue)
    }

    private func handle(connectionState: NWConnection.State, conn: NWConnection) {
        switch connectionState {
        case .ready:
            if let endpoint = conn.endpoint as? NWEndpoint.hostPort {
                let host = "\(endpoint.host)"
                let port = "\(endpoint.port)"
                state = .connected(address: "\(host):\(port)")
            } else {
                state = .connected(address: "unknown")
            }
            receiveLoop(conn)
        case .failed, .cancelled:
            let ip = LocalNetwork.currentIPv4() ?? "127.0.0.1"
            state = .listening(address: LocalNetwork.formatAddress(ip: ip, port: port))
            connection = nil
        default:
            break
        }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data = data, !data.isEmpty {
                if let messages = try? BridgeMessage.decode(Buffer: data, ctx: self.parseContext) {
                    for msg in messages { self.onMessage(msg) }
                }
            }
            if isComplete || error != nil {
                let ip = LocalNetwork.currentIPv4() ?? "127.0.0.1"
                self.state = .listening(address: LocalNetwork.formatAddress(ip: ip, port: self.port))
                self.connection = nil
                return
            }
            self.receiveLoop(conn)
        }
    }
}
```

- [ ] **步骤 4：运行测试，确认通过**

```bash
cd ios && swift test --filter TerminalServerTests
```
预期：PASS。

- [ ] **步骤 5：提交**

```bash
git add ios/ClaudeRemote/Sources/TerminalServer.swift ios/Tests/ClaudeRemoteTests/TerminalServerTests.swift
git commit -m "feat(ios): add NWListener TCP server with message dispatch"
```

---

## Task 8：iOS — 终端会话状态机

**文件：**
- 修改：`ios/ClaudeRemote/Sources/TerminalSession.swift`
- 创建：`ios/Tests/ClaudeRemoteTests/TerminalSessionTests.swift`

- [ ] **步骤 1：写失败测试**

创建 `ios/Tests/ClaudeRemoteTests/TerminalSessionTests.swift`：

```swift
import Testing
import Foundation
@testable import ClaudeRemoteLib

@Suite struct TerminalSessionTests {
    @Test func 初始为idle() {
        let s = TerminalSession()
        #expect(s.phase == .idle)
    }

    @Test func start用配置端口启动服务器() throws {
        let s = TerminalSession(port: 19090)
        s.start()
        #expect(s.phase == .starting || s.phase == .listening)
        s.stop()
    }

    @Test func hello消息转为running() {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0", cols: 80, rows: 24))
        #expect(s.phase == .running)
        s.stop()
    }

    @Test func output消息追加到receivedBytes() throws {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0"))
        let b64 = "hi".data(using: .utf8)!.base64EncodedString()
        s.handleMessage(BridgeMessage(type: .output, data: b64))
        #expect(s.receivedBytes == Data([0x68, 0x69]))
        s.stop()
    }

    @Test func exit消息转为exited() {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0"))
        s.handleMessage(BridgeMessage(type: .exit, code: 0, signal: nil))
        #expect(s.phase == .exited(code: 0))
        s.stop()
    }

    @Test func sendInput转发到服务器() throws {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0"))
        let captured = SentCapture()
        s.serverSender = { msg in captured.messages.append(msg) }
        let b64 = "x".data(using: .utf8)!.base64EncodedString()
        s.sendInput(Data([0x78]))
        #expect(captured.messages.count == 1)
        #expect(captured.messages[0].type == .input)
        #expect(captured.messages[0].data == b64)
        s.stop()
    }
}

private final class SentCapture {
    var messages: [BridgeMessage] = []
}
```

- [ ] **步骤 2：运行测试，确认失败**

```bash
cd ios && swift test --filter TerminalSessionTests
```
预期：FAIL —— `TerminalSession.phase`、`.running`、`.exited(code:)` 等未定义。

- [ ] **步骤 3：写最小实现**

替换 `ios/ClaudeRemote/Sources/TerminalSession.swift`：

```swift
import Foundation
import Combine

enum SessionPhase: Equatable {
    case idle
    case starting
    case listening(address: String)
    case running
    case exited(code: Int)
    case failed(String)

    static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.starting, .starting), (.running, .running): return true
        case (.listening(let a), .listening(let b)): return a == b
        case (.exited(let a), .exited(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

final class TerminalSession: ObservableObject {
    @Published var phase: SessionPhase = .idle
    @Published var receivedBytes: Data = Data()
    @Published var statusText: String = "Idle"
    let port: UInt16
    var serverSender: ((BridgeMessage) -> Void)?

    private var server: TerminalServer?

    init(port: UInt16 = 8080) {
        self.port = port
        // 不自动 start()——由 ClaudeRemoteApp.onAppear 启动，让 TerminalSession() 创建后保持 idle（见测试「初始为idle」）
    }

    func start() {
        guard server == nil else { return }
        phase = .starting
        do {
            let server = try TerminalServer(
                port: port,
                onMessage: { [weak self] msg in
                    DispatchQueue.main.async { self?.handleMessage(msg) }
                },
                onStateChange: { [weak self] state in
                    DispatchQueue.main.async { self?.handle(serverState: state) }
                }
            )
            self.server = server
            self.serverSender = { [weak server] msg in server?.send(msg) }
            server.start()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        phase = .idle
    }

    func handleMessage(_ msg: BridgeMessage) {
        switch msg.type {
        case .hello:
            phase = .running
        case .output:
            if let b64 = msg.data, let bytes = Data(base64Encoded: b64) {
                receivedBytes.append(bytes)
            }
        case .exit:
            let code = msg.code ?? 0
            phase = .exited(code: code)
        case .error:
            if let m = msg.message { phase = .failed(m) }
        default:
            break
        }
    }

    func sendInput(_ data: Data) {
        let msg = BridgeMessage(type: .input, data: data.base64EncodedString())
        serverSender?(msg)
    }

    func sendResize(cols: Int, rows: Int) {
        let msg = BridgeMessage(type: .resize, cols: cols, rows: rows)
        serverSender?(msg)
    }

    private func handle(serverState: ServerState) {
        switch serverState {
        case .idle:
            if phase != .running { phase = .idle }
        case .starting:
            phase = .starting
        case .listening(let addr):
            if phase != .running { phase = .listening(address: addr) }
            statusText = "Listening on \(addr)"
        case .connected:
            statusText = "Bridge connected"
        case .failed(let msg):
            phase = .failed(msg)
        case .stopping:
            break
        }
    }
}
```

- [ ] **步骤 4：运行测试，确认通过**

```bash
cd ios && swift test --filter TerminalSessionTests
```
预期：PASS。

- [ ] **步骤 5：提交**

```bash
git add ios/ClaudeRemote/Sources/TerminalSession.swift ios/Tests/ClaudeRemoteTests/TerminalSessionTests.swift
git commit -m "feat(ios): add TerminalSession state machine wiring server to UI"
```

---

## Task 9：iOS — SwiftTerm 包装（UIViewRepresentable）

**文件：**
- 创建：`ios/ClaudeRemote/Views/TerminalScreen.swift`

本任务无单元测试——SwiftTerm 渲染是 UIKit 视图，在无头环境里无法有意义地单元测试。由 Task 13 的集成验证覆盖。

- [ ] **步骤 1：创建包装**

创建 `ios/ClaudeRemote/Views/TerminalScreen.swift`：

```swift
import SwiftUI
import SwiftTerm

struct TerminalScreen: UIViewRepresentable {
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void
    let feed: () -> Data?  // 返回自上次调用以来待投喂的字节

    func makeUIView(context: Context) -> LocalTerminalView {
        let tv = LocalTerminalView()
        tv.terminalDelegate = context.coordinator
        tv.feedBuffer = feed
        return tv
    }

    func updateUIView(_ uiView: LocalTerminalView, context: Context) {
        // 排空待处理字节
        while let chunk = feed() {
            uiView.feed(byteArray: Array(chunk))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let onInput: (Data) -> Void
        let onResize: (Int, Int) -> Void

        init(onInput: @escaping (Data) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func send(_ source: TerminalView, data: [UInt8]) {
            onInput(Data(data))
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}

/// 子类：暴露 feed buffer 给 SwiftUI 更新使用。
final class LocalTerminalView: TerminalView {
    var feedBuffer: (() -> Data?)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let feed = feedBuffer {
            while let chunk = feed() {
                self.feed(byteArray: Array(chunk))
            }
        }
    }
}
```

- [ ] **步骤 2：验证包仍能构建**

```bash
cd ios && swift build
```
预期：构建成功（SwiftTerm import 解析通过）。

- [ ] **步骤 3：提交**

```bash
git add ios/ClaudeRemote/Views/TerminalScreen.swift
git commit -m "feat(ios): wrap SwiftTerm in UIViewRepresentable with input/resize callbacks"
```

---

## Task 10：iOS — 连接信息视图

**文件：**
- 创建：`ios/ClaudeRemote/Views/ConnectionInfoView.swift`

无单元测试（纯展示视图）。

- [ ] **步骤 1：创建视图**

创建 `ios/ClaudeRemote/Views/ConnectionInfoView.swift`：

```swift
import SwiftUI

struct ConnectionInfoView: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(session.statusText)
                    .font(.system(.body, design: .monospaced))
            }
            if case .listening(let addr) = session.phase {
                Label("Bridge 命令：", systemImage: "terminal")
                    .font(.system(.caption, design: .monospaced))
                Text("  node bridge.js \(addr)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private var statusIcon: String {
        switch session.phase {
        case .idle: return "circle.dashed"
        case .starting: return "arrow.triangle.2.circlepath"
        case .listening: return "wifi"
        case .running: return "checkmark.circle.fill"
        case .exited: return "arrow.uturn.backward.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .running: return .green
        case .failed: return .red
        case .exited: return .orange
        default: return .blue
        }
    }
}
```

- [ ] **步骤 2：提交**

```bash
git add ios/ClaudeRemote/Views/ConnectionInfoView.swift
git commit -m "feat(ios): add connection info view with bridge command hint"
```

---

## Task 11：iOS — 键盘 accessory bar

**文件：**
- 创建：`ios/ClaudeRemote/Views/KeyboardAccessory.swift`

无单元测试（纯输入视图）。行为由 Task 13 集成验证覆盖。

- [ ] **步骤 1：创建 accessory bar**

创建 `ios/ClaudeRemote/Views/KeyboardAccessory.swift`：

```swift
import SwiftUI

struct KeyboardAccessory: View {
    let onKey: (String) -> Void

    private let keys: [(label: String, sends: String)] = [
        ("ESC", "\u{1B}"),
        ("TAB", "\t"),
        ("CTRL", "\u{1}"),      // 哨兵值 —— 由 coordinator 切换 ctrl 模式处理
        ("↑", "\u{1B}[A"),
        ("↓", "\u{1B}[B"),
        ("←", "\u{1B}[D"),
        ("→", "\u{1B}[C"),
        ("HOME", "\u{1B}[H"),
        ("END", "\u{1B}[F"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys.indices, id: \.self) { idx in
                Button(keys[idx].label) { onKey(keys[idx].sends) }
                    .buttonStyle(KeyButtonStyle())
            }
            Spacer()
            Button("/") { onKey("/") }
                .buttonStyle(KeyButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
    }
}

private struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.4) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}
```

- [ ] **步骤 2：提交**

```bash
git add ios/ClaudeRemote/Views/KeyboardAccessory.swift
git commit -m "feat(ios): add keyboard accessory bar with ESC/TAB/arrows"
```

---

## Task 12：iOS — 主视图组装

**文件：**
- 修改：`ios/ClaudeRemote/Views/MainView.swift`

无单元测试（视图组装由构建验证）。

- [ ] **步骤 1：用完整组装替换 MainView**

替换 `ios/ClaudeRemote/Views/MainView.swift`：

```swift
import SwiftUI
import SwiftTerm

struct MainView: View {
    @ObservedObject var session: TerminalSession
    @AppStorage("claudeRemote.port") private var portSetting: Int = 8080
    @AppStorage("claudeRemote.fontSize") private var fontSize: Double = 13
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectionInfoView(session: session)
                .padding(.horizontal)
                .padding(.top, 8)

            TerminalScreen(
                onInput: { data in session.sendInput(data) },
                onResize: { cols, rows in session.sendResize(cols: cols, rows: rows) },
                feed: { session.drainPendingBytes() }
            )
            .ignoresSafeArea(.keyboard)

            KeyboardAccessory(onKey: { seq in
                session.sendInput(seq.data(using: .utf8) ?? Data())
            })
        }
        .navigationTitle("ClaudeRemote")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(port: $portSetting, fontSize: $fontSize)
        }
    }
}
```

- [ ] **步骤 2：给 TerminalSession 加 drainPendingBytes**

在 `ios/ClaudeRemote/Sources/TerminalSession.swift` 的 `TerminalSession` 类里加：

```swift
    /// 排空并返回下一块待渲染字节给 SwiftTerm。
    func drainPendingBytes() -> Data? {
        if receivedBytes.isEmpty { return nil }
        let chunk = receivedBytes
        receivedBytes = Data()
        return chunk
    }
```

- [ ] **步骤 3：创建 Settings 视图占位**

创建 `ios/ClaudeRemote/Views/SettingsView.swift`：

```swift
import SwiftUI

struct SettingsView: View {
    @Binding var port: Int
    @Binding var fontSize: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    Stepper(value: $port, in: 1024...65535) {
                        Text("端口：\(port)")
                    }
                }
                Section("终端") {
                    Slider(value: $fontSize, in: 9...20) {
                        Text("字体大小")
                    }
                    Text(String(format: "%.0f pt", fontSize))
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **步骤 4：验证构建**

```bash
cd ios && swift build
```
预期：构建成功。

- [ ] **步骤 5：提交**

```bash
git add ios/ClaudeRemote/Views/MainView.swift ios/ClaudeRemote/Sources/TerminalSession.swift ios/ClaudeRemote/Views/SettingsView.swift
git commit -m "feat(ios): assemble main view with terminal + accessory + settings"
```

---

## Task 13：GitHub Actions — 构建 + 打包 IPA

**文件：**
- 创建：`.github/workflows/build-ipa.yml`
- 创建：`ios/ExportOptions.plist`
- 创建：`ios/scripts/package-ipa.sh`
- 创建：`ios/project.yml`（XcodeGen 规格）
- 创建：`ios/scripts/gen-xcodeproj.sh`

- [ ] **步骤 1：创建导出选项 plist**

创建 `ios/ExportOptions.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>ad-hoc</string>
    <key>compileBitcode</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string></string>
    <key>thinning</key>
    <string></string>
</dict>
</plist>
```

- [ ] **步骤 2：创建打包脚本**

创建 `ios/scripts/package-ipa.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

# 用法：package-ipa.sh <.app路径> <输出ipa路径>
APP_PATH="$1"
OUT_IPA="$2"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: .app not found at $APP_PATH" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
PAYLOAD_DIR="$WORK_DIR/Payload"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

# ad-hoc 签名 app 包（TrollStore 会接受）。
codesign --force --deep --sign - "$PAYLOAD_DIR/$(basename "$APP_PATH")"

# 打包成 .ipa
(cd "$WORK_DIR" && zip -r -q "$OUT_IPA" Payload)
echo "Packaged IPA: $OUT_IPA"
```

赋予可执行权限：

```bash
chmod +x ios/scripts/package-ipa.sh
```

- [ ] **步骤 3：创建 XcodeGen 规格**

由于 SPM 单独无法生成 iOS 的 `.ipa`，我们在 runner 上用 `xcodegen` 生成 Xcode 工程。创建 `ios/project.yml`：

```yaml
name: ClaudeRemote
options:
  bundleIdPrefix: com.clauderemote
  deploymentTarget:
    iOS: "16.0"
  developmentLanguage: en
settings:
  base:
    SWIFT_VERSION: "5.9"
    IPHONEOS_DEPLOYMENT_TARGET: "16.0"
    TARGETED_DEVICE_FAMILY: "1,2"
    CODE_SIGN_IDENTITY: ""
    CODE_SIGNING_REQUIRED: NO
    CODE_SIGNING_ALLOWED: NO
packages:
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm.git
    from: "1.2.0"
targets:
  ClaudeRemote:
    type: application
    platform: iOS
    sources:
      - path: ClaudeRemote
    info:
      path: ClaudeRemote/Info.plist
      properties:
        CFBundleDisplayName: ClaudeRemote
        UILaunchScreen: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.clauderemote.app
        PRODUCT_NAME: ClaudeRemote
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ENABLE_PREVIEWS: YES
    dependencies:
      - package: SwiftTerm
```

创建 `ios/scripts/gen-xcodeproj.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

xcodegen generate --spec project.yml
echo "Generated ClaudeRemote.xcodeproj"
```

赋予可执行权限：

```bash
chmod +x ios/scripts/gen-xcodeproj.sh
```

- [ ] **步骤 4：写 GitHub Actions workflow**

创建 `.github/workflows/build-ipa.yml`：

```yaml
name: Build iOS IPA

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 15
        run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer

      - name: Install xcodegen
        run: brew install xcodegen

      - name: Generate Xcode project
        working-directory: ios
        run: xcodegen generate --spec project.yml

      - name: Build app
        working-directory: ios
        run: |
          xcodebuild \
            -project ClaudeRemote.xcodeproj \
            -scheme ClaudeRemote \
            -configuration Release \
            -sdk iphoneos \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            -destination "generic/platform=iOS"

      - name: Package IPA
        run: |
          APP_PATH="ios/build/Build/Products/Release-iphoneos/ClaudeRemote.app"
          ./ios/scripts/package-ipa.sh "$APP_PATH" ClaudeRemote.ipa

      - name: Upload IPA artifact
        uses: actions/upload-artifact@v4
        with:
          name: ClaudeRemote-ipa
          path: ClaudeRemote.ipa
          if-no-files-found: error

      - name: Attach IPA to release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: ClaudeRemote.ipa
```

- [ ] **步骤 5：验证 workflow 语法（本地）**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-ipa.yml'))" && echo "YAML OK"
```
预期：`YAML OK`。

- [ ] **步骤 6：提交**

```bash
git add .github/workflows/build-ipa.yml ios/ExportOptions.plist ios/scripts/ ios/project.yml
git commit -m "ci: add GitHub Actions workflow to build and package IPA for TrollStore"
```

---

## Task 14：集成测试 — 端到端手动验证

本任务无自动化测试（需要真实 iPad + UTM）。它记录验证流程。

**文件：**
- 创建：`bridge/README.md`

- [ ] **步骤 1：写 bridge 安装文档**

创建 `bridge/README.md`：

````markdown
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
````

- [ ] **步骤 2：写 iOS 安装文档（TrollStore）**

在 `bridge/README.md` 末尾追加：

````markdown

## 安装 iOS 应用（TrollStore）

1. 从 GitHub Actions 的 artifacts（或 Releases）下载 `ClaudeRemote.ipa`。
2. 在 iPad 上打开 TrollStore（支持 iOS 16.6.1）。
3. 点 **+**，选择 `.ipa` 文件。
4. 安装后从主屏幕启动 **ClaudeRemote**。
5. 弹窗时授予本地网络权限。

## 自己构建 IPA

推送 `v1.0.0` tag 触发 GitHub Actions 构建，或在 Actions 标签页手动运行 workflow。下载 artifact，用 TrollStore 安装。
````

- [ ] **步骤 3：提交**

```bash
git add bridge/README.md
git commit -m "docs: add bridge setup and TrollStore install guide"
```

---

## Task 15：根 README

**文件：**
- 创建：`README.md`

- [ ] **步骤 1：创建根 README**

创建 `README.md`：

````markdown
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
````

- [ ] **步骤 2：提交**

```bash
git add README.md
git commit -m "docs: add root README with architecture and quick start"
```

---

## 自我审查

**1. 规格覆盖：**
- iOS 应用远控 Claude Code → Task 4–12（基于 SwiftTerm 终端的 iOS 应用）
- UTM/Alpine 目标 → Task 1–3（bridge）、Task 14（Alpine 安装文档）
- agnes（非官方模型）→ 无需特殊处理；bridge 直接跑你 Alpine 里已配置好的 `claude`，env 变量（`ANTHROPIC_BASE_URL` 等）原样继承（Task 14 README 有文档）
- iPad Pro 2021 / iOS 16.6.1 → Info.plist 目标 iOS 16；TrollStore 支持 16.6.1
- GitHub Actions 构建 IPA → Task 13
- TrollStore 分发 → Task 13 ad-hoc 签名 + Task 14 安装文档
- "完美适配 Claude Code" → SwiftTerm 渲染完整 xterm-256color TUI（光标、颜色、box-drawing、对话框）

**2. 占位扫描：**
- 无 TBD/TODO/"稍后实现" 字样。
- 每个代码步骤都有完整代码。
- 每条命令都有预期输出。
- 发现一处缺口已修：`drainPendingBytes()` 在 Task 12 被引用，已在 Task 12 步骤 2 内联定义。✓
- `LocalNetwork.currentIPv4()` 在 Task 7 和 Task 10 被引用；在 Task 6 定义。✓

**3. 类型一致性：**
- `BridgeMessage` 字段（`type`、`version`、`cols`、`rows`、`data`、`code`、`signal`、`message`）在 Node protocol（Task 1）、Swift `Message.swift`（Task 5）和所有调用点一致。
- `MessageType` case（`hello`、`output`、`exit`、`input`、`resize`、`error`）与 Task 1 的 Node `VALID_TYPES` 集合一致。
- `SessionPhase` enum case 在 `ConnectionInfoView`（Task 10）使用，与 `TerminalSession`（Task 8）定义一致：`idle`、`starting`、`listening(address:)`、`running`、`exited(code:)`、`failed(String)`。✓
- `TerminalServer` 初始化签名 `(port:onMessage:onStateChange:)` 在 Task 7 与 Task 8 一致。✓
- `ServerState` case 在 `TerminalSession.handle(serverState:)` 使用，与 `TerminalServer` 定义一致。✓

**审查中发现并修复的缺口：**
- 给 Task 12 步骤 2 加了 `drainPendingBytes()`（被引用但未定义）。
- 确认 `LocalNetwork.formatAddress(ip:port:)` 签名在 Task 6、Task 7、Task 10 完全一致。

---

## 执行交接

**计划已完成并保存到 `docs/superpowers/plans/2026-06-30-claude-code-ios-remote.md`。两种执行方式：**

**1. Subagent-Driven（推荐）** — 每个任务派发独立 subagent，任务间审查，迭代快。

**2. Inline Execution** — 在当前会话里逐任务执行，批量推进 + 检查点审查。

**选哪种？**
