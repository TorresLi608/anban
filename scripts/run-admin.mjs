import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const address = process.env.ANBAN_ADMIN_ADDR || '127.0.0.1:8025';
const match = /^(\[[^\]]+\]|[^:/?#\s]+):(\d+)$/.exec(address);
if (!match || Number(match[2]) < 1 || Number(match[2]) > 65535) {
  console.error('ANBAN_ADMIN_ADDR 必须是 host:port，例如 127.0.0.1:8025，不能包含 http://。');
  process.exit(1);
}

const child = spawn(process.execPath, [
  fileURLToPath(new URL('../admin/node_modules/next/dist/bin/next', import.meta.url)),
  'dev', fileURLToPath(new URL('../admin/', import.meta.url)),
  '--hostname', match[1].replace(/^\[|\]$/g, ''), '--port', match[2],
  ...process.argv.slice(2),
], { stdio: 'inherit' });
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => child.kill(signal));
}
child.once('error', error => {
  console.error(`管理端启动失败：${error.message}`);
  process.exit(1);
});
child.once('exit', (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
