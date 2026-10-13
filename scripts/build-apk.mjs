import { copyFileSync, mkdirSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = fileURLToPath(new URL('..', import.meta.url));
const mobile = join(root, 'mobile');
const args = process.argv.slice(2);

function argumentValue(name) {
  const inline = args.find((value) => value.startsWith(`${name}=`));
  if (inline) return inline.slice(name.length + 1);
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function pubspecVersion() {
  const contents = readFileSync(join(mobile, 'pubspec.yaml'), 'utf8');
  const match = /^version:\s*([^+\s]+)(?:\+(\S+))?\s*$/m.exec(contents);
  if (!match) throw new Error('mobile/pubspec.yaml 中没有有效的 version');
  return { name: match[1], number: match[2] };
}

const configured = pubspecVersion();
const versionName = argumentValue('--build-name') || configured.name;
const versionNumber = argumentValue('--build-number') || configured.number;
if (!/^\d+(?:\.\d+){0,2}$/.test(versionName)) {
  throw new Error(`无效的版本名称：${versionName}`);
}
if (versionNumber && !/^\d+$/.test(versionNumber)) {
  throw new Error(`无效的版本编号：${versionNumber}`);
}

function hasApiDefine() {
  return args.some((value, index) =>
    value.startsWith('--dart-define=ANBAN_API_URL=') ||
    (value === '--dart-define' && args[index + 1]?.startsWith('ANBAN_API_URL=')),
  );
}

// `flutter build apk` defaults to release. Pass the configured API URL unless
// the caller supplied an explicit dart-define, so release APKs do not fall
// back to the localhost default compiled into the app.
const flutterArgs = ['build', 'apk', ...args];
const apiUrl = process.env.ANBAN_API_URL?.trim();
if (apiUrl && !hasApiDefine()) {
  flutterArgs.push(`--dart-define=ANBAN_API_URL=${apiUrl}`);
}

const result = spawnSync('flutter', flutterArgs, {
  cwd: mobile,
  stdio: 'inherit',
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);

const outputDir = join(mobile, 'build', 'app', 'outputs', 'flutter-apk');
const buildType = args.includes('--debug')
  ? 'debug'
  : args.includes('--profile')
    ? 'profile'
    : 'release';
const source = join(outputDir, `app-${buildType}.apk`);
const targetName = buildType === 'release'
  ? `anban-${versionName}.apk`
  : `anban-${versionName}-${buildType}.apk`;
const target = join(outputDir, targetName);
mkdirSync(outputDir, { recursive: true });
copyFileSync(source, target);
console.log(`APK（${buildType}）：${target}`);
