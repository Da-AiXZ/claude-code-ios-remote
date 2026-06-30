import { EventEmitter } from 'node:events';
import pty from 'node-pty';

// PtyManager：包装 node-pty，spawn 子进程并把 I/O 以 base64 编码暴露给调用方。
export class PtyManager extends EventEmitter {
  constructor({ command, args = [], cwd, env = process.env, cols = 80, rows = 24 }) {
    super();
    // 必须提供要 spawn 的命令
    if (!command) throw new Error('command is required');
    this.command = command;
    this.args = args;
    this.cols = cols;
    this.rows = rows;
    // 显式保证 SHELL 环境变量被设置：claude CLI 启动时检查 $SHELL，
    // 没设置会报 "No suitable shell found. Claude CLI requires a Posix shell environment."
    // 在 Alpine 上直接 UTM 控制台登录或 su - 切换用户时 SHELL 经常没被设置，
    // 这里兜底设为 /bin/sh（Alpine 默认 POSIX shell），允许调用方传入的 env.SHELL 覆盖。
    const finalEnv = { ...env };
    if (!finalEnv.SHELL) finalEnv.SHELL = '/bin/sh';
    if (!finalEnv.TERM) finalEnv.TERM = 'xterm-256color';
    this._proc = pty.spawn(command, args, {
      name: 'xterm-256color',
      cols,
      rows,
      cwd: cwd || process.env.HOME,
      env: finalEnv,
    });
    // 子进程输出：编码成 base64 后 emit
    this._proc.onData((data) => {
      this.emit('output', Buffer.from(data, 'utf8').toString('base64'));
    });
    // 子进程退出：把 exitCode/signal 转成统一的 { code, signal } 结构 emit
    this._proc.onExit(({ exitCode, signal }) => {
      this.emit('exit', { code: exitCode, signal: signal || null });
    });
  }

  // 把 base64 输入解码后写入 PTY
  write(b64) {
    const data = Buffer.from(b64, 'base64').toString('utf8');
    this._proc.write(data);
  }

  // 调整 PTY 尺寸
  resize(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    this._proc.resize(cols, rows);
  }

  // 杀掉子进程
  kill() {
    this._proc.kill();
  }
}
