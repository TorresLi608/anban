import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, existsSync, rmSync } from 'node:fs';
import { createServer, createConnection } from 'node:net';
import { tmpdir } from 'node:os';
import { join, delimiter } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';

async function waitFor(check) {
  for (let i = 0; i < 100; i++) { if (await check()) return; await delay(50); }
  throw new Error('Timed out waiting for process/port');
}
const portOpen = port => new Promise(resolve => {
  const socket = createConnection({ host: '127.0.0.1', port });
  socket.once('connect', () => { socket.destroy(); resolve(true); });
  socket.once('error', () => resolve(false));
});

test('backend replaces occupied port and releases child listener on SIGINT', { timeout: 15000 }, async () => {
  const root = mkdtempSync(join(tmpdir(), 'anban-lifecycle-'));
  for (const name of ['scripts', 'backend', 'bin']) mkdirSync(join(root, name));
  copyFileSync(new URL('./run-backend.mjs', import.meta.url), join(root, 'scripts/run-backend.mjs'));
  const reserve = createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening');
  const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
  const ready = join(root, 'ready');
  const listener = `require('node:net').createServer().listen(${port},'127.0.0.1',()=>require('node:fs').writeFileSync(${JSON.stringify(ready)},'ready'));`;
  writeFileSync(join(root, 'bin/go'), `#!/usr/bin/env node\nconst child=require('node:child_process').spawn(process.execPath,['-e',${JSON.stringify(listener)}],{stdio:'inherit'});child.on('exit',code=>process.exit(code??1));\n`, { mode: 0o700 });
  const occupied = spawn(process.execPath, ['-e', `require('node:net').createServer().listen(${port},'127.0.0.1')`]);
  const occupiedExit = once(occupied, 'exit');
  let launcher;
  try {
    await waitFor(() => portOpen(port));
    launcher = spawn(process.execPath, [join(root, 'scripts/run-backend.mjs')], {
      env: { ...process.env, ANBAN_ADDR: `127.0.0.1:${port}`, PATH: `${join(root,'bin')}${delimiter}${process.env.PATH}` },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let output = ''; launcher.stdout.on('data', b => { output += b; }); launcher.stderr.on('data', b => { output += b; });
    const exited = once(launcher, 'exit');
    await waitFor(() => existsSync(ready));
    await occupiedExit;
    assert.match(output, /正在结束进程/);
    assert.equal(await portOpen(port), true);
    launcher.kill('SIGINT');
    const [code] = await exited;
    assert.equal(code, 130);
    await waitFor(async () => !await portOpen(port));
  } finally {
    occupied.kill('SIGTERM');
    if (launcher && launcher.exitCode === null) { launcher.kill('SIGTERM'); await once(launcher, 'exit'); }
    rmSync(root, { recursive: true, force: true });
  }
});
