import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const [platform, deviceId] = process.argv.slice(2);
const cwd = fileURLToPath(new URL('../mobile/', import.meta.url));

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!['android', 'ios', 'web'].includes(platform)) fail('请选择 android、ios 或 web。');

function launch(device, extra = []) {
  const fallback = platform === 'android' && device.emulator
    ? 'http://10.0.2.2:8024' : 'http://localhost:8024';
  const api = process.env.ANBAN_API_URL?.trim() || fallback;
  const result = spawnSync('flutter', ['run', '-d', device.id, ...extra, `--dart-define=ANBAN_API_URL=${api}`], { cwd, stdio: 'inherit' });
  if (result.error) fail(`Flutter 启动失败：${result.error.message}`);
  process.exit(result.status ?? 1);
}

if (platform === 'web') launch({ id: 'chrome' }, ['--web-port', '7357']);

const discovery = spawnSync('flutter', ['devices', '--machine'], {
  cwd,
  encoding: 'utf8',
  stdio: ['inherit', 'pipe', 'inherit'],
});
if (discovery.error) fail(`无法运行 Flutter：${discovery.error.message}`);
if (discovery.status !== 0) process.exit(discovery.status ?? 1);

let devices;
try {
  devices = JSON.parse(discovery.stdout).filter((device) =>
    device.isSupported !== false &&
    (platform === 'ios' ? device.targetPlatform === 'ios' : device.targetPlatform?.startsWith('android')) &&
    (!deviceId || device.id === deviceId),
  );
} catch {
  fail('无法解析 Flutter 设备列表，请运行 flutter devices 检查环境。');
}

if (devices.length !== 1) {
  fail(devices.length === 0
    ? `未找到可用的 ${platform} 设备${deviceId ? `（${deviceId}）` : ''}。请连接手机或启动模拟器；可用 flutter emulators 查看、flutter emulators --launch <模拟器ID> 启动。`
    : `检测到多个 ${platform} 设备，请指定：npm run ${platform} -- <设备ID>\n${devices.map((d) => `${d.id}  ${d.name}`).join('\n')}`);
}

launch(devices[0]);
