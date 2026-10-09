import assert from 'node:assert/strict';
import test from 'node:test';
import { shouldUseSecureCookie } from '../src/lib/session-cookie.ts';

test('session cookies follow the browser protocol and keep HTTPS secure behind proxies', () => {
  for (const [headers, secure] of [
    [{ origin: 'http://203.0.113.10:8025' }, false],
    [{ origin: 'https://admin.example.com' }, true],
    [{ origin: 'https://admin.example.com', 'x-forwarded-proto': 'http' }, true],
    [{ origin: 'http://localhost:8025', 'x-forwarded-proto': 'https' }, false],
    [{ 'x-forwarded-proto': 'http' }, false],
    [{ 'x-forwarded-proto': 'https, http' }, true],
    [{ 'x-forwarded-proto': 'http, https' }, false],
    [{ origin: 'null', 'x-forwarded-proto': 'http' }, true],
    [{ origin: 'invalid', 'x-forwarded-proto': 'http' }, true],
    [{}, true],
  ]) {
    assert.equal(shouldUseSecureCookie(new Headers(headers)), secure, JSON.stringify(headers));
  }
});
