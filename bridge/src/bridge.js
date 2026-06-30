import net from 'node:net';
import { serialize, parse, MessageError } from './protocol.js';
import { PtyManager } from './pty-manager.js';

// 桥接主线路：作为 TCP 客户端连接 iOS 应用，spawn PTY，双向转发 I/O，断线自动重连。
export function connectBridge({ host, port, command, args = [], cwd, reconnectDelayMs = 3000 }) {
  let closed = false;
  let pty = null;
  let activeSocket = null;
  // 跨数据包复用的协议解析缓冲区
  const parserCtx = { buffer: '' };

  function connect() {
    if (closed) return;
    const sock = net.connect(port, host);
    activeSocket = sock;

    sock.on('connect', () => {
      console.log(`[bridge] connected to ${host}:${port}`);
      pty = new PtyManager({ command, args, cwd });
      sock.write(serialize({ type: 'hello', version: '1.0.0', cols: pty.cols, rows: pty.rows }));

      // PTY 输出 → socket
      pty.on('output', (b64) => {
        if (sock.writable) sock.write(serialize({ type: 'output', data: b64 }));
      });
      // PTY 退出 → 发 exit 消息并结束 socket
      pty.on('exit', ({ code, signal }) => {
        if (sock.writable) sock.write(serialize({ type: 'exit', code, signal }));
        sock.end();
      });
    });

    // socket 输入 → PTY（input/resize）
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

    // 断线：清理 PTY，定时重连
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

// CLI 入口：node src/bridge.js <host> <port> [claude-command]
if (import.meta.url === `file://${process.argv[1]}`) {
  const host = process.argv[2] || '127.0.0.1';
  const port = parseInt(process.argv[3] || '8080', 10);
  const command = process.env.CLAUDE_PATH || process.argv[4] || 'claude';
  console.log(`[bridge] starting → ${host}:${port}, command=${command}`);
  connectBridge({ host, port, command, args: [], cwd: process.env.HOME });
}
