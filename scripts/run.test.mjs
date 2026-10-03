import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, delimiter, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

test('mobile scripts choose the requested platform and propagate failures', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'anban-launch-'));
  const output = join(temporary, 'invocation.json');
  const launcher = fileURLToPath(new URL('./run-mobile.mjs', import.meta.url));
  const devices = [
    { id: 'emulator-5554', name: 'Pixel', targetPlatform: 'android-arm64', emulator: true },
    { id: 'iphone-test', name: 'iPhone', targetPlatform: 'ios' },
    { id: 'chrome', name: 'Chrome', targetPlatform: 'web-javascript' },
  ];
  writeFileSync(join(temporary, 'flutter'), `#!/usr/bin/env node
if (process.argv[2] === 'devices') {
  process.stdout.write(process.env.TEST_DEVICES);
} else {
  require('node:fs').writeFileSync(process.env.TEST_OUTPUT, JSON.stringify({args:process.argv.slice(2), cwd:process.cwd()}));
  process.exit(Number(process.env.TEST_EXIT || 0));
}
`, { mode: 0o700 });
  const run = (args, list = devices, exit = 0, api = '') => spawnSync(process.execPath, [launcher, ...args], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${temporary}${delimiter}${process.env.PATH}`, TEST_DEVICES: JSON.stringify(list), TEST_OUTPUT: output, TEST_EXIT: String(exit), ANBAN_API_URL: api },
  });
  try {
    for (const [platform, id] of [['android', 'emulator-5554'], ['ios', 'iphone-test']]) {
      assert.equal(run([platform]).status, 0);
      const invocation = JSON.parse(readFileSync(output, 'utf8'));
      assert.deepEqual(invocation.args, ['run', '-d', id, `--dart-define=ANBAN_API_URL=${platform === 'android' ? 'http://10.0.2.2:8024' : 'http://localhost:8024'}`]);
      assert.equal(resolve(invocation.cwd), fileURLToPath(new URL('../mobile', import.meta.url)));
    }
    assert.equal(run(['android'], devices, 0, 'https://api.example.com').status, 0);
    assert.equal(JSON.parse(readFileSync(output, 'utf8')).args.at(-1), '--dart-define=ANBAN_API_URL=https://api.example.com');
    assert.equal(run(['android'], []).status, 1);
    assert.equal(run(['android', 'iphone-test']).status, 1);
    const multiple = [...devices, { ...devices[0], id: 'second-android' }];
    assert.match(run(['android'], multiple).stderr, /多个 android 设备/);
    assert.equal(run(['android', 'second-android'], multiple).status, 0);
    assert.equal(run(['ios'], devices, 7).status, 7);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('root web and backend scripts use the correct directory and load .env', () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'anban-npm-')));
  try {
    for (const folder of ['mobile', 'backend', 'scripts', 'bin']) mkdirSync(join(root, folder));
    copyFileSync(new URL('../package.json', import.meta.url), join(root, 'package.json'));
    for (const file of ['run-backend.mjs', 'run-mobile.mjs']) copyFileSync(new URL(`./${file}`, import.meta.url), join(root, 'scripts', file));
    writeFileSync(join(root, '.env'), 'ANBAN_TOKEN=test-only-token-with-at-least-32-characters\nANBAN_ORIGINS=http://localhost:7357\nANBAN_API_URL=http://10.0.2.2:8024\nMINIO_SECRET_KEY=must-not-be-compiled\n');
    writeFileSync(join(root, 'bin', 'lsof'), '#!/bin/sh\nexit 1\n', { mode: 0o700 });
    const output = join(root, 'result.json');
    const mock = '#!/usr/bin/env node\nrequire("node:fs").writeFileSync(process.env.TEST_OUTPUT, JSON.stringify({args:process.argv.slice(2),cwd:process.cwd(),token:process.env.ANBAN_TOKEN,origins:process.env.ANBAN_ORIGINS}));\n';
    for (const command of ['flutter', 'go']) writeFileSync(join(root, 'bin', command), mock, { mode: 0o700 });
    const env = { ...process.env, PATH: `${join(root, 'bin')}${delimiter}${process.env.PATH}`, TEST_OUTPUT: output };
    delete env.ANBAN_TOKEN;
    delete env.ANBAN_ORIGINS;
    delete env.ANBAN_API_URL;
    for (const [command, folder, args] of [['web', 'mobile', ['run', '-d', 'chrome', '--web-port', '7357', '--dart-define=ANBAN_API_URL=http://10.0.2.2:8024']], ['backend', 'backend', ['run', '.']]]) {
      const result = spawnSync(process.execPath, ['--run', command], { cwd: root, env, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
      const actual = JSON.parse(readFileSync(output, 'utf8'));
      assert.equal(actual.cwd, join(root, folder));
      assert.deepEqual(actual.args, args);
      assert.ok(!actual.args.some(arg => arg.includes('must-not-be-compiled')));
      if (command === 'backend') {
        assert.equal(actual.token, 'test-only-token-with-at-least-32-characters');
        assert.equal(actual.origins, 'http://localhost:7357');
      }
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
