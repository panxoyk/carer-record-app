import test from 'node:test';
import assert from 'node:assert/strict';
import { stopEnvironment } from './stop-env.mjs';
import { runEnvironment } from './run-env.mjs';

const validMount = JSON.stringify([{ Type: 'volume', Name: 'carer-record-hapi-data', Destination: '/data/hapi' }]);
function fake({ mounts = validMount, datasource = 'true', exists = true } = {}) {
  const calls = [];
  return { calls, run: async (name, args) => {
    calls.push([name, args]);
    if (args[0] === 'ps' && args[1] === '-a') return exists ? 'carer-record-hapi-fhir\n' : '';
    if (args[0] === 'inspect' && args.includes('{{json .Mounts}}')) return mounts;
    if (args[0] === 'inspect' && args.some((x) => x.includes('.Config.Env'))) return datasource;
    if (args[0] === 'inspect' && args.some((x) => x.includes('.NetworkSettings.Networks'))) return JSON.stringify({ 'supabase_network_carer-record': {} });
    return '';
  } };
}

test('env:stop detaches HAPI before stopping it and Supabase, without deleting volumes', async () => {
  const f = fake();
  await stopEnvironment({ run: f.run });
  const commands = f.calls.map(([, args]) => args.join(' '));
  const detach = commands.findIndex((x) => x.includes('network disconnect'));
  const hapiStop = commands.findIndex((x) => x.includes('compose') && x.includes('stop hapi-fhir'));
  const supabaseStop = commands.findIndex((x) => x.includes('supabase stop'));
  assert.ok(detach >= 0 && hapiStop > detach && supabaseStop > hapiStop);
  assert.equal(commands.some((x) => /down -v|--no-backup|volume rm/.test(x)), false);
});

test('env:stop refuses legacy HAPI without stopping anything', async () => {
  const f = fake({ mounts: '[]' });
  await assert.rejects(stopEnvironment({ run: f.run }), /Refusing to stop HAPI/);
  assert.equal(f.calls.some(([, args]) => args[0] === 'compose' || args.includes('stop')), false);
});

test('env:stop is idempotent when HAPI is absent and still stops Supabase', async () => {
  const f = fake({ exists: false });
  await stopEnvironment({ run: f.run });
  assert.deepEqual(f.calls.map(([, args]) => args), [['ps', '-a', '--format', '{{.Names}}'], ['exec', 'supabase', 'stop']]);
});

test('a guarded env:stop sequence can be followed by env:up again', async () => {
  const order = [];
  const stopped = fake();
  await stopEnvironment({ run: async (name, args) => { order.push(`stop:${args.join(' ')}`); return stopped.run(name, args); } });
  const signal = new AbortController();
  const calls = [];
  const run = (name, args) => {
    calls.push([name, args]);
    order.push(`up:${args.join(' ')}`);
    let output = '';
    if (name === 'docker' && args[0] === 'ps') output = '';
    if (name === 'docker' && args[0] === 'network' && args[1] === 'inspect') output = 'carer-record-hapi-fhir\n';
    return { done: Promise.resolve({ code: 0, output, stderr: '' }), stop: async () => {} };
  };
  await runEnvironment({ env: { SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test' }, onSignal: false, signal: signal.signal,
    runner: { run, start: run, cleanup: async () => {} },
    fetcher: async (url) => new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405 }),
    sleep: async () => signal.abort(),
  });
  const stopSupabase = order.findIndex((entry) => entry === 'stop:exec supabase stop');
  const restartSupabase = order.findIndex((entry) => entry === 'up:exec supabase start');
  assert.ok(stopSupabase >= 0 && restartSupabase > stopSupabase);
  assert.ok(calls.some(([, args]) => args[0] === 'compose' && args.includes('up')));
});
