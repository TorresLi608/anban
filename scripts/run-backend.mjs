import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const result = spawnSync('go', ['run', '.'], {
  cwd: fileURLToPath(new URL('../backend/', import.meta.url)),
  stdio: 'inherit',
});
if (result.error) console.error(`Go 后端启动失败：${result.error.message}`);
process.exit(result.status ?? 1);
