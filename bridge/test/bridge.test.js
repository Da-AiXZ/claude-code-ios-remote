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
