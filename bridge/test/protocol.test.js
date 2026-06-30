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
