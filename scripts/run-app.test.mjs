import test from 'node:test';
import assert from 'node:assert/strict';
import { runApp, hasPersistentHapiData } from './run-app.mjs';

const env = { SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test', SUPABASE_URL: 'http://127.0.0.1:54321' };

function fakeRunner() {
  const calls = [];
  const run = (name, args, options = {}) => {
    calls.push({ name, args, options });
    return { done: Promise.resolve({ code: 0, output: '', stderr: '' }), stop: async () => { calls.push({ stop: true }); } };
  };
  return { calls, run, start: run, cleanup: async () => {} };
}

test('app:run invokes only Flutter with caller args and configured Supabase URL', async () => {
  for (const argument of ['--profile', '--release']) {
    const runner = fakeRunner();
    const code = await runApp({ args: [argument], env: { ...env, SUPABASE_URL: 'http://10.0.2.2:54321' }, runner, onSignal: false, fetcher: async () => new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405 }) });
    assert.equal(code, 0);
    assert.equal(runner.calls.some(({ name }) => name === 'docker' || name === 'pnpm'), false);
    const flutter = runner.calls.find(({ name, options }) => name === 'fvm' && options.interactive);
    assert.ok(flutter.args.includes(argument));
    assert.ok(flutter.args.includes('--dart-define=SUPABASE_URL=http://10.0.2.2:54321'));
    assert.equal(runner.calls.some(({ stop }) => stop), false);
  }
});

test('app:run reports actionable env:up instruction without running Flutter when gateway is unavailable', async () => {
  const runner = fakeRunner();
  assert.equal(await runApp({ env, runner, onSignal: false, fetcher: async () => { throw new Error('not ready'); } }), 1);
  assert.equal(runner.calls.some(({ name }) => name === 'fvm' || name === 'docker' || name === 'pnpm'), false);
});

test('app:run rejects the legacy gateway-only mode instead of starting a service', async () => {
  const runner = fakeRunner();
  assert.equal(await runApp({ args: ['--gateway-only'], env, runner, onSignal: false }), 1);
  assert.equal(runner.calls.length, 0);
});

test('HAPI persistence guard requires the exact volume, mount and datasource', () => {
  assert.equal(hasPersistentHapiData([{ Type: 'volume', Name: 'carer-record-hapi-data', Destination: '/data/hapi' }], 'true'), true);
  assert.equal(hasPersistentHapiData([], 'true'), false);
  assert.equal(hasPersistentHapiData([{ Type: 'bind', Name: 'carer-record-hapi-data', Destination: '/data/hapi' }], 'true'), false);
  assert.equal(hasPersistentHapiData([{ Type: 'volume', Name: 'carer-record-hapi-data', Destination: '/data/hapi' }], ''), false);
});
