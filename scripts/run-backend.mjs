import { spawn, spawnSync } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const address = process.env.ANBAN_ADDR || '127.0.0.1:8024';
const match = /^(?:\[[^\]]+\]|[^:/?#]*):(\d+)$/.exec(address);
if (!match || Number(match[1]) < 1 || Number(match[1]) > 65535) {
  console.error('ANBAN_ADDR 必须是 host:port，例如 127.0.0.1:8024；客户端 URL 请填写 ANBAN_API_URL。');
  process.exit(1);
}
const port = Number(match[1]);
if (process.platform === 'win32') {
  console.error('此启动脚本使用 POSIX 进程组和 lsof，请在 macOS、Linux 或 WSL 运行。');
  process.exit(1);
}

function listeners() {
  const result = spawnSync('lsof', ['-nP', '-t', `-iTCP:${port}`, '-sTCP:LISTEN'], { encoding: 'utf8' });
  if (result.error) throw new Error('无法检查端口，请先安装 lsof。');
  if (result.status !== 0 && (result.status !== 1 || result.stderr.trim())) {
    throw new Error(`无法检查端口 ${port}：${result.stderr.trim()}`);
  }
  return [...new Set(result.stdout.trim().split(/\s+/).filter(Boolean).map(Number))];
}
function kill(pid, signal) {
  try { process.kill(pid, signal); }
  catch (error) { if (error.code !== 'ESRCH') throw error; }
}

let child;
let stopping = false;
async function stop(code) {
  if (stopping) return;
  stopping = true;
  // Kill only our process group on exit, never whoever now owns the port.
  if (child?.pid) {
    try {
      kill(-child.pid, 'SIGTERM');
      await delay(1000);
      kill(-child.pid, 'SIGKILL');
    } catch (error) { console.error(`关闭后端失败：${error.message}`); code = 1; }
  }
  process.exit(code);
}
for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 143], ['SIGHUP', 129]]) {
  process.on(signal, () => { void stop(code); });
}

try {
  const occupied = listeners();
  if (occupied.length) {
    console.log(`端口 ${port} 已被占用，正在结束进程：${occupied.join(', ')}`);
    for (const pid of occupied) kill(pid, 'SIGTERM');
    for (let i = 0; i < 20 && listeners().some(pid => occupied.includes(pid)); i++) await delay(100);
    for (const pid of listeners().filter(pid => occupied.includes(pid))) kill(pid, 'SIGKILL');
    for (let i = 0; i < 10 && listeners().length; i++) await delay(100);
    if (listeners().length) throw new Error(`端口 ${port} 仍被占用，请检查权限或自动重启的服务。`);
  }
  if (!stopping) {
    child = spawn('go', ['run', '.'], {
      cwd: fileURLToPath(new URL('../backend/', import.meta.url)),
      env: { ...process.env, ANBAN_ADDR: address },
      stdio: 'inherit',
      detached: true,
    });
    child.once('error', error => { console.error(`Go 后端启动失败：${error.message}`); void stop(1); });
    child.once('exit', (code, signal) => { void stop(code ?? (signal ? 1 : 0)); });
  }
} catch (error) {
  console.error(`后端启动失败：${error.message}`);
  await stop(1);
}
