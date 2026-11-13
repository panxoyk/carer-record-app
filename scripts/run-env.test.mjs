import test from 'node:test';
import assert from 'node:assert/strict';
import { runEnvironment } from './run-env.mjs';

const env = { SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test', SUPABASE_LOCAL_URL: 'http://127.0.0.1:54321', HAPI_FHIR_PORT: '8123' };
const persistentMount = JSON.stringify([{ Type: 'volume', Name: 'carer-record-hapi-data', Destination: '/data/hapi' }]);

function fixture({ prior = 'missing', mounts = persistentMount, datasource = 'true', fail = '', clock, gatewayDone } = {}) {
  const calls = [];
  let gatewayStops = 0;
  let cleanups = 0;
  const execute = async (name, args, options = {}) => {
    calls.push({ name, args, options });
    if (fail && args.some((arg) => String(arg).includes(fail))) return { code: 1, output: '', stderr: 'fixture failure' };
    if (name === 'docker' && args[0] === 'ps' && args.includes('-a')) return { code: 0, output: prior === 'missing' ? '' : 'carer-record-hapi-fhir\n' };
    if (name === 'docker' && args[0] === 'inspect' && args.some((x) => x.includes('NetworkSettings.Networks'))) return { code: 0, output: prior === 'stale' ? JSON.stringify({ obsolete: { NetworkID: 'old' } }) : '{}' };
    if (name === 'docker' && args[0] === 'network' && args[1] === 'ls') return { code: 0, output: '' };
    if (name === 'docker' && args[0] === 'inspect' && args.some((x) => x.includes('.Mounts'))) return { code: 0, output: mounts };
    if (name === 'docker' && args[0] === 'inspect' && args.some((x) => x.includes('.Config.Env'))) return { code: 0, output: datasource };
    if (name === 'docker' && args[0] === 'network' && args[1] === 'inspect') return { code: 0, output: 'carer-record-hapi-fhir\n' };
    return { code: 0, output: '' };
  };
  const runner = {
    calls,
    run: (name, args, options) => ({ done: execute(name, args, options), stop: async () => {} }),
    start: (name, args, options) => {
      calls.push({ name, args, options, started: true });
      return { done: gatewayDone ?? new Promise(() => {}), stop: async () => { gatewayStops++; } };
    },
    cleanup: async () => { cleanups++; },
  };
  return { calls, runner, get gatewayStops() { return gatewayStops; }, get cleanups() { return cleanups; } };
}

const fetchReady = async (url) => url.includes('/functions/v1/')
  ? new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405 })
  : new Response('{}', { status: 200 });

test('env:up reuses validated durable HAPI and orders bootstrap, daily events, sync, assignments and gateway without Flutter', async () => {
  const f = fixture({ prior: 'attached' });
  const abort = new AbortController();
  const code = await runEnvironment({ env, runner: f.runner, signal: abort.signal, onSignal: false, fetcher: fetchReady, sleep: async () => abort.abort() });
  assert.equal(code, 130);
  const indexes = [
    f.calls.findIndex(({ args }) => args.some((x) => String(x).endsWith('bootstrap-demo.mjs'))),
    f.calls.findIndex(({ args }) => args.some((x) => String(x).endsWith('ensure-demo-current-events.mjs'))),
    f.calls.findIndex(({ args }) => args.some((x) => String(x).endsWith('generate-sync.mjs')) && args.includes('--apply')),
    f.calls.findIndex(({ args }) => args.includes('--demo-assignments')),
  ];
  assert.ok(indexes[0] >= 0 && indexes[1] > indexes[0] && indexes[2] > indexes[1] && indexes[3] > indexes[2]);
  assert.equal(f.calls.some(({ name }) => name === 'fvm'), false);
  assert.ok(f.calls.some(({ args }) => args[0] === 'compose' && args.includes('up') && args.includes('hapi-fhir')));
  assert.equal(f.gatewayStops, 1);
  assert.equal(f.calls.some(({ name, args }) => name === 'docker' && (args.includes('stop') || args.includes('down'))), false);
  const daily = f.calls.find(({ args }) => args.some((x) => String(x).endsWith('ensure-demo-current-events.mjs')));
  assert.equal(daily.options.env.FHIR_DEMO_TIMEZONE, 'America/Santiago');
  assert.equal(daily.options.env.FHIR_BASE_URL, 'http://127.0.0.1:8123/fhir');
  assert.equal(f.calls.some(({ args }) => args.some((x) => String(x).includes('SELECT timezone'))), false);
});

test('env:up tolerates fewer than three gateway probe failures, then abort cleans only its gateway', async () => {
  const f = fixture();
  const abort = new AbortController();
  let calls = 0;
  let pauses = 0;
  const fetcher = async (url) => {
    if (!url.includes('/functions/v1/')) return new Response('{}', { status: 200 });
    calls++;
    if (calls === 2) throw new Error('transient failure');
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405 });
  };
  const code = await runEnvironment({ env, runner: f.runner, signal: abort.signal, onSignal: false, fetcher, sleep: async () => { if (++pauses === 2) abort.abort(); } });
  assert.equal(code, 130);
  assert.equal(calls, 3);
  assert.equal(f.gatewayStops, 1);
  assert.equal(f.calls.some(({ name, args }) => name === 'docker' && (args.includes('stop') || args.includes('down'))), false);
});

test('env:up exits nonzero after repeated gateway failures while Supabase remains reachable', async () => {
  const f = fixture();
  let gatewayProbes = 0;
  const fetcher = async (url) => {
    if (!url.includes('/functions/v1/')) return new Response('{}', { status: 503 });
    gatewayProbes++;
    if (gatewayProbes === 1) return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405 });
    throw new Error('gateway unavailable');
  };
  assert.equal(await runEnvironment({ env, runner: f.runner, onSignal: false, fetcher, sleep: async () => {} }), 1);
  assert.equal(gatewayProbes, 4);
  assert.equal(f.gatewayStops, 1);
});

test('env:up refuses in-memory HAPI and datasource mismatch before compose up', async () => {
  for (const options of [{ mounts: '[]' }, { datasource: '' }]) {
    const f = fixture({ prior: 'attached', ...options });
    assert.equal(await runEnvironment({ env, runner: f.runner, onSignal: false }), 1);
    assert.equal(f.calls.some(({ name, args }) => name === 'docker' && args.includes('up')), false);
    assert.equal(f.gatewayStops, 0);
  }
});

test('env:up blocks gateway on bootstrap or daily-event failure', async () => {
  for (const failedScript of ['bootstrap-demo.mjs', 'ensure-demo-current-events.mjs']) {
    const f = fixture({ fail: failedScript });
    assert.equal(await runEnvironment({ env, runner: f.runner, onSignal: false }), 1);
    assert.equal(f.calls.some(({ started }) => started), false);
  }
});

test('env:up reruns daily events when startup crosses America/Santiago midnight', async () => {
  const f = fixture();
  const abort = new AbortController();
  let instant = new Date('2026-11-12T23:59:00Z');
  let probes = 0;
  const fetcher = async (url) => {
    if (url.includes('/functions/v1/')) {
      probes++;
      if (probes === 1) instant = new Date('2026-11-13T04:30:00Z');
      return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405 });
    }
    return new Response('{}', { status: 200 });
  };
  const code = await runEnvironment({ env, runner: f.runner, signal: abort.signal, onSignal: false, fetcher, now: () => instant, sleep: async () => abort.abort() });
  assert.equal(code, 130);
  assert.equal(f.calls.filter(({ args }) => args.some((x) => String(x).endsWith('ensure-demo-current-events.mjs'))).length, 2);
});

test('env:up cleans its gateway after unexpected gateway exit and does not kill containers', async () => {
  const f = fixture({ gatewayDone: Promise.resolve({ code: 8, stderr: 'gateway crashed' }) });
  assert.equal(await runEnvironment({ env, runner: f.runner, onSignal: false, fetcher: fetchReady }), 8);
  assert.equal(f.gatewayStops, 1);
  assert.equal(f.calls.some(({ name, args }) => name === 'docker' && (args.includes('stop') || args.includes('down'))), false);
});
