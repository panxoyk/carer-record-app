import { mkdir, open, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { assertHapiVersionZeroCreateSupport, HAPI_VERSION_ZERO_MATCH } from './hapi-create-only.mjs';

const LIMITS = { pages: 500, resources: 100_000, bytes: 20_000_000, totalBytes: 100_000_000, archiveBytes: 100_000_000 };
const synthetic = (r) => r?.meta?.tag?.some((t) => t.system === 'http://terminology.hl7.org/CodeSystem/v3-ActReason' && t.code === 'HTEST') === true;
const identity = (r) => {
  if (!r || !/^[A-Z][A-Za-z0-9]{0,63}$/.test(r.resourceType ?? '') || !/^[A-Za-z0-9.-]{1,64}$/.test(r.id ?? '')) throw new Error('Invalid FHIR resource identity');
  return `${r.resourceType}/${r.id}`;
};
function checkedBase(value) {
  const u = new URL(value);
  if (u.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(u.hostname) || u.username || u.password || u.search || u.hash) throw new Error('Transfer only permits credential-free HTTP loopback FHIR URLs');
  u.pathname = `${u.pathname.replace(/\/$/, '')}/`;
  return u;
}
async function json(response, budget) {
  if (!response.ok) throw new Error(`FHIR transfer request failed: HTTP ${response.status}`);
  const reader = response.body?.getReader();
  if (!reader) throw new Error('FHIR transfer response body is missing');
  const chunks = []; let bytes = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > LIMITS.bytes) { await reader.cancel(); throw new Error('FHIR transfer response exceeds size limit'); }
    if (budget && budget.used + bytes > budget.max) { await reader.cancel(); throw new Error('FHIR transfer total byte limit exceeded'); }
    chunks.push(value);
  }
  if (budget) budget.used += bytes;
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new Error('FHIR transfer response is invalid JSON'); }
}
async function readArchive(path) {
  const handle = await open(path, 'r'); const chunks = []; let bytes = 0;
  try {
    const buffer = Buffer.alloc(64 * 1024);
    while (true) {
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, null);
      if (!bytesRead) break;
      bytes += bytesRead;
      if (bytes > LIMITS.archiveBytes) throw new Error('FHIR transfer archive exceeds size limit');
      chunks.push(Buffer.from(buffer.subarray(0, bytesRead)));
    }
  } finally { await handle.close(); }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new Error('FHIR transfer archive is invalid JSON'); }
}
function nextUrl(raw, base) {
  const u = new URL(raw, base);
  if (u.origin !== base.origin || !u.pathname.startsWith(base.pathname)) throw new Error('FHIR paging link leaves the selected local server');
  return u;
}
async function pages(url, base, fetchImpl, budget) {
  const entries = []; const visited = new Set();
  for (let page = 0; url; page++) {
    if (page >= LIMITS.pages || visited.has(url.href)) throw new Error('FHIR transfer paging limit or cycle detected');
    visited.add(url.href);
    const bundle = await json(await fetchImpl(url, { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(15_000) }), budget);
    if (bundle.resourceType !== 'Bundle' || !['searchset', 'history'].includes(bundle.type)) throw new Error('FHIR transfer expected a search/history Bundle');
    entries.push(...(bundle.entry ?? []).map((e) => e.resource).filter(Boolean));
    if (entries.length > LIMITS.resources) throw new Error('FHIR transfer resource limit exceeded');
    const link = bundle.link?.find((x) => x.relation === 'next')?.url;
    url = link ? nextUrl(link, base) : null;
  }
  return entries;
}
export async function exportSynthetic({ baseUrl, output, fetchImpl = fetch }) {
  const base = checkedBase(baseUrl);
  const budget = { used: 0, max: LIMITS.totalBytes };
  const cap = await json(await fetchImpl(new URL('metadata', base), { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(15_000) }), budget);
  if (cap.resourceType !== 'CapabilityStatement' || !/^4\.0\./.test(cap.fhirVersion ?? '')) throw new Error('Source must be an R4 CapabilityStatement');
  const types = [...new Set((cap.rest ?? []).flatMap((r) => r.resource ?? []).map((r) => r.type).filter((x) => /^[A-Z][A-Za-z0-9]{0,63}$/.test(x)))].sort();
  const current = [];
  for (const type of types) current.push(...await pages(new URL(`${type}?_count=100`, base), base, fetchImpl, budget));
  if (!current.length || current.some((r) => !synthetic(r))) throw new Error('Export refused: source contains resources not explicitly tagged HTEST synthetic');
  const history = []; let historyComplete = true;
  for (const type of types) {
    try { history.push(...await pages(new URL(`${type}/_history?_count=100`, base), base, fetchImpl, budget)); }
    catch { historyComplete = false; break; }
  }
  if (history.some((r) => !synthetic(r))) throw new Error('History contains resources not explicitly tagged HTEST synthetic');
  const archive = { format: 'cra-hapi-synthetic-export-v1', source: base.href, exportedAt: new Date().toISOString(), historyComplete, warning: 'Restore preserves Resource.id, not source version IDs; history completeness depends on source support.', current, history };
  const path = resolve(output); await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(archive, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
  return { path, current: current.length, history: history.length, historyComplete };
}
export async function restoreSynthetic({ baseUrl, input, fetchImpl = fetch }) {
  const base = checkedBase(baseUrl); const archive = await readArchive(input);
  if (archive.format !== 'cra-hapi-synthetic-export-v1' || !Array.isArray(archive.current) || archive.current.some((r) => !synthetic(r))) throw new Error('Invalid or non-synthetic archive');
  const expected = new Map(archive.current.map((resource) => [identity(resource), resource]));
  if (expected.size !== archive.current.length) throw new Error('Archive contains duplicate FHIR identities');
  const capability = await json(await fetchImpl(new URL('metadata', base), { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(15_000) }));
  assertHapiVersionZeroCreateSupport(capability, [...new Set([...expected.values()].map(({ resourceType }) => resourceType))]);
  const observed = new Map();
  for (const [key, resource] of expected) {
    const url = new URL(key.split('/').map(encodeURIComponent).join('/'), base);
    const response = await fetchImpl(url, { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(15_000) });
    if (response.status === 404) { observed.set(key, false); continue; }
    if (response.status !== 200) throw new Error(`Restore preflight failed: HTTP ${response.status}`);
    const existing = await json(response);
    const expectedSubject = resource.subject?.reference ?? resource.patient?.reference;
    const actualSubject = existing.subject?.reference ?? existing.patient?.reference;
    if (!synthetic(existing) || identity(existing) !== key || (expectedSubject && actualSubject !== expectedSubject) || (resource.encounter?.reference && existing.encounter?.reference !== resource.encounter.reference)) throw new Error(`Existing ${key} has conflicting synthetic identity or references`);
    observed.set(key, true);
  }
  let created = 0; let unchanged = 0;
  for (const [key, resource] of expected) {
    if (observed.get(key)) { unchanged++; continue; }
    const url = new URL(key.split('/').map(encodeURIComponent).join('/'), base);
    const response = await fetchImpl(url, { method: 'PUT', headers: { 'Content-Type': 'application/fhir+json', Accept: 'application/fhir+json', 'If-Match': HAPI_VERSION_ZERO_MATCH }, body: JSON.stringify(resource), redirect: 'error', signal: AbortSignal.timeout(15_000) });
    if (response.status === 201) { created++; continue; }
    if ([409, 412].includes(response.status)) {
      const reread = await fetchImpl(url, { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(15_000) });
      if (reread.status === 200) {
        const actual = await json(reread);
        const expectedSubject = resource.subject?.reference ?? resource.patient?.reference;
        const actualSubject = actual.subject?.reference ?? actual.patient?.reference;
        if (synthetic(actual) && identity(actual) === key && (!expectedSubject || actualSubject === expectedSubject) && (!resource.encounter?.reference || actual.encounter?.reference === resource.encounter.reference)) { unchanged++; continue; }
      }
    }
    throw new Error(`Create-only restore failed with HTTP ${response.status}`);
  }
  return { created, unchanged, sourceVersionIdsPreserved: false };
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [action, ...args] = process.argv.slice(2); const flags = Object.fromEntries(args.filter((x) => x.startsWith('--')).map((x) => { const [k, v = true] = x.slice(2).split('='); return [k, v]; }));
  try {
    if (action === 'export') {
      if (!args.includes('--confirm-synthetic')) throw new Error('Exporting all local FHIR data requires --confirm-synthetic');
      console.log(JSON.stringify(await exportSynthetic({ baseUrl: flags.url ?? `http://127.0.0.1:${process.env.HAPI_FHIR_PORT ?? 8080}/fhir`, output: flags.output ?? 'docker/hapi-fhir/exports/hapi-synthetic.json' })));
    } else if (action === 'restore') {
      if (!flags.input) throw new Error('restore requires --input=ARCHIVE');
      console.log(JSON.stringify(await restoreSynthetic({ baseUrl: flags.url ?? `http://127.0.0.1:${process.env.HAPI_FHIR_PORT ?? 8080}/fhir`, input: flags.input })));
    } else throw new Error('Usage: hapi-data-transfer.mjs export --confirm-synthetic [--url=URL] [--output=FILE] | restore --input=FILE [--url=URL]');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
