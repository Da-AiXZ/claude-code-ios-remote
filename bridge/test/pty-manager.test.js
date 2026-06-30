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
