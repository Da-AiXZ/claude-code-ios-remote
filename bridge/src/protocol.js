// 消息协议模块：把消息对象序列化为换行分隔的 JSON，并从字节流中解析消息。
// PTY 二进制数据由调用方自行 base64 编码后放入 data 字段。

// 协议错误类型，用于区分普通异常与协议解析异常。
export class MessageError extends Error {}

// 合法的消息类型集合。
const VALID_TYPES = new Set(['hello', 'output', 'exit', 'input', 'resize', 'error']);

// 把消息对象序列化为 UTF-8 Buffer，并以换行结尾。
export function serialize(message) {
  if (!message || typeof message.type !== 'string' || !VALID_TYPES.has(message.type)) {
    throw new MessageError(`Invalid message type: ${message?.type}`);
  }
  return Buffer.from(JSON.stringify(message) + '\n', 'utf8');
}

// 有状态解析器：传入 context 对象，跨调用复用未结束的 buffer。
export function parse(chunk, ctx = { buffer: '' }) {
  ctx.buffer += chunk.toString('utf8');
  const messages = [];
  let idx;
  // 反复切出每一行（以 \n 分隔），直到没有完整行可切。
  while ((idx = ctx.buffer.indexOf('\n')) >= 0) {
    const line = ctx.buffer.slice(0, idx);
    ctx.buffer = ctx.buffer.slice(idx + 1);
    const trimmed = line.trim();
    // 跳过空行。
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
