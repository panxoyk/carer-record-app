#!/usr/bin/env node
import { parseEnv } from "node:util";
import { readFile, access } from "node:fs/promises";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const repo = resolve(root, "..");
const composeFile = resolve(repo, "docker/hapi-fhir/docker-compose.yml");
const NETWORK = "supabase_network_carer-record";
const HAPI = "carer-record-hapi-fhir";

export function buildInvocation(
  name,
  args,
  platform = process.platform,
  env = process.env,
) {
  if (platform !== "win32")
    return { file: name, args, options: { shell: false } };
  if (name === process.execPath || name === "docker")
    return { file: name, args, options: { shell: false } };
  const envValue = (key) =>
    Object.entries(env).find(
      ([k]) => k.toLowerCase() === key.toLowerCase(),
    )?.[1];
  const dirs = (envValue("PATH") ?? "").split(";");
  const suffixes = (envValue("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD").split(";");
  if (/\.(?:exe|com)$/i.test(name))
    return { file: name, args, options: { shell: false } };
  const quote = (arg) => {
    if (/[\r\n%!"]/u.test(arg))
      throw new Error(
        "command arguments cannot be safely represented on Windows",
      );
    return `"${arg}"`;
  };
  const cmd = envValue("ComSpec") || "cmd.exe";
  const launcher = dirs
    .flatMap((dir) =>
      suffixes.map((ext) => resolve(dir, `${name}${ext.toLowerCase()}`)),
    )
    .find(existsSync);
  const executable = launcher ?? `${name}.cmd`;
  if (/\.(?:exe|com)$/i.test(executable))
    return { file: executable, args, options: { shell: false } };
  const command = `${quote(executable)} ${args.map(quote).join(" ")}`;
  const script = `"${command}"`;
  return {
    file: cmd,
    args: ["/d", "/s", "/c", script],
    options: { shell: false, windowsVerbatimArguments: true },
  };
}

export function validate(input) {
  const env = { ...input };
  env.SUPABASE_LOCAL_URL ??= "http://127.0.0.1:54321";
  env.SUPABASE_URL ??= env.SUPABASE_LOCAL_URL;
  const key = env.SUPABASE_PUBLISHABLE_KEY ?? "";
  let isPublishable = key.startsWith("sb_publishable_");
  if (key.startsWith("eyJ")) {
    try {
      isPublishable =
        JSON.parse(Buffer.from(key.split(".")[1], "base64url").toString())
          .role === "anon";
    } catch {
      isPublishable = false;
    }
  }
  if (!isPublishable || key === "sb_publishable_")
    throw new Error(
      "configuration: SUPABASE_PUBLISHABLE_KEY must be a publishable or anon key",
    );
  const mobile = parseUrl(env.SUPABASE_URL, "SUPABASE_URL");
  const local = parseUrl(env.SUPABASE_LOCAL_URL, "SUPABASE_LOCAL_URL");
  if (
    local.username ||
    local.password ||
    local.pathname !== "/" ||
    local.search ||
    local.hash ||
    !["127.0.0.1", "localhost", "::1", "[::1]"].includes(local.hostname)
  )
    throw new Error(
      "configuration: SUPABASE_LOCAL_URL must be a loopback base URL",
    );
  if (
    mobile.username ||
    mobile.password ||
    mobile.pathname !== "/" ||
    mobile.search ||
    mobile.hash
  )
    throw new Error(
      "configuration: SUPABASE_URL must be a base URL without credentials, path, query or fragment",
    );
  const rawPort = env.HAPI_FHIR_PORT ?? "8080";
  if (!/^\d+$/.test(rawPort) || Number(rawPort) < 1 || Number(rawPort) > 65535)
    throw new Error("configuration: invalid HAPI_FHIR_PORT");
  return { ...env, HAPI_FHIR_PORT: String(Number(rawPort)) };
}
function parseUrl(value, key) {
  try {
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol)) throw Error();
    return url;
  } catch {
    throw new Error(`configuration: invalid ${key}`);
  }
}

export function createRunner({
  env = process.env,
  platform = process.platform,
  cwd = repo,
} = {}) {
  const owned = new Set();
  const run = (name, args, options = {}) => {
    if (options.signal?.aborted) {
      return {
        done: Promise.resolve({ code: null, reason: "cancelled" }),
        stop: async () => {},
      };
    }
    const invocation = buildInvocation(
      name,
      args,
      platform,
      options.env ?? env,
    );
    const child = spawn(invocation.file, invocation.args, {
      cwd: options.cwd ?? cwd,
      env: options.env ?? env,
      ...invocation.options,
      stdio: options.interactive ? "inherit" : ["ignore", "pipe", "pipe"],
      detached: platform !== "win32" && !options.interactive,
    });
    child.ownsGroup = platform !== "win32" && !options.interactive;
    owned.add(child);
    const interactiveTree =
      options.interactive && platform !== "win32"
        ? trackInteractiveTree(child)
        : null;
    let output = "";
    let stderr = "";
    const appendBounded = (current, chunk) => (current + chunk).slice(-16_384);
    child.stdout?.on("data", (chunk) => {
      output = appendBounded(output, chunk);
    });
    child.stderr?.on("data", (chunk) => {
      stderr = appendBounded(stderr, chunk);
    });
    let timedOut = false;
    const done = new Promise((resolvePromise) => {
      child.once("error", () => {
        if (!interactiveTree) owned.delete(child);
        resolvePromise({ code: null, reason: "command unavailable" });
      });
      child.once("close", (code, signal) => {
        if (!interactiveTree) owned.delete(child);
        else void interactiveTree.snapshot();
        resolvePromise({ code, signal, timedOut, output, stderr });
      });
    });
    let stopping;
    const stop = () =>
      (stopping ??= (
        interactiveTree
          ? terminateInteractive(child, interactiveTree)
          : terminate(child, platform)
      ).finally(() => owned.delete(child)));
    const abort = () => stop();
    options.signal?.addEventListener("abort", abort, { once: true });
    const timeout =
      options.timeout ?? (options.interactive ? 0 : timeoutFor(options.stage));
    const timer =
      timeout > 0
        ? setTimeout(() => {
            timedOut = true;
            void stop();
          }, timeout)
        : null;
    done.finally(() => {
      if (timer) clearTimeout(timer);
      options.signal?.removeEventListener("abort", abort);
    });
    return {
      child,
      done,
      stop,
      aborted: () => options.signal?.aborted ?? false,
    };
  };
  const cleanup = async () => {
    await Promise.all(
      [...owned].map((child) =>
        child.interactiveTree
          ? terminateInteractive(child, child.interactiveTree)
          : terminate(child, platform),
      ),
    );
    owned.clear();
  };
  return { run, start: run, cleanup };
}
function timeoutFor(stage = "") {
  if (/preflight fvm flutter/i.test(stage)) return 5 * 60_000;
  if (/seed|Supabase startup|HAPI startup/i.test(stage)) return 15 * 60_000;
  if (/sync|assignments/i.test(stage)) return 2 * 60_000;
  return 30_000;
}
export function failureReason(stderr = "", code) {
  if (
    /cannot connect to.*docker|docker daemon.*(?:not running|unavailable)|is the docker daemon running/i.test(
      stderr,
    )
  )
    return "Docker daemon unavailable";
  if (
    /address already in use|port is already allocated|ports are not available/i.test(
      stderr,
    )
  )
    return "port already in use";
  if (/network .+ not found/i.test(stderr)) return "Docker network not found";
  if (/connection refused|could not connect to server/i.test(stderr))
    return "connection refused";
  if (/relation .+ does not exist|pending migrations/i.test(stderr))
    return "database schema missing or outdated";
  if (
    /no such host|temporary failure in name resolution|ENOTFOUND/i.test(stderr)
  )
    return "host name could not be resolved";
  return `exited ${code ?? "abnormally"}`;
}
function terminate(child, platform) {
  if (!child.pid || child.exitCode !== null || child.signalCode !== null)
    return Promise.resolve();
  if (platform === "win32") {
    const killer = spawn(
      "taskkill.exe",
      ["/pid", String(child.pid), "/t", "/f"],
      { stdio: "ignore", windowsHide: true },
    );
    return new Promise((resolvePromise) => {
      killer.once("error", resolvePromise);
      killer.once("close", resolvePromise);
    });
  }
  try {
    if (child.ownsGroup) process.kill(-child.pid, "SIGTERM");
    else child.kill("SIGTERM");
  } catch {
    try {
      child.kill("SIGTERM");
    } catch {}
  }
  return new Promise((resolvePromise) => {
    const t = setTimeout(() => {
      try {
        if (child.ownsGroup) process.kill(-child.pid, "SIGKILL");
        else child.kill("SIGKILL");
      } catch {}
      resolvePromise();
    }, 1500);
    child.once("close", () => {
      clearTimeout(t);
      resolvePromise();
    });
  });
}

// Interactive children inherit the caller's TTY and cannot be detached into
// their own process group. Track only descendants observed beneath this pid;
// never signal the runner's foreground process group or unrelated processes.
function trackInteractiveTree(child) {
  const identities = new Map();
  let rootIdentity;
  const snapshot = async () => {
    const rows = await listProcesses();
    const byPid = new Map(rows.map((row) => [row.pid, row]));
    const root = byPid.get(child.pid);
    if (
      !rootIdentity &&
      child.exitCode === null &&
      child.signalCode === null &&
      root
    )
      rootIdentity = root.identity;
    const rootIsActive =
      rootIdentity &&
      child.exitCode === null &&
      child.signalCode === null &&
      root?.identity === rootIdentity;
    const known = new Set(rootIsActive ? [child.pid] : []);
    for (const [pid, identity] of identities) {
      if (byPid.get(pid)?.identity === identity) known.add(pid);
    }
    let changed = true;
    while (changed) {
      changed = false;
      for (const row of rows) {
        if (known.has(row.ppid) && !known.has(row.pid)) {
          known.add(row.pid);
          identities.set(row.pid, row.identity);
          changed = true;
        }
      }
    }
    // Preserve previously observed descendants after their parent exits, but
    // require the same start-time identity to avoid acting on a reused PID.
    return { rows, known, byPid };
  };
  const poll = setInterval(() => void snapshot(), 250);
  poll.unref();
  void snapshot();
  child.interactiveTree = { snapshot, poll, identities };
  return child.interactiveTree;
}

async function listProcesses() {
  const ps = spawn("ps", ["-axo", "pid=,ppid=,lstart="], {
    stdio: ["ignore", "pipe", "ignore"],
  });
  let output = "";
  ps.stdout.on("data", (chunk) => {
    output += chunk;
  });
  const code = await new Promise((resolvePromise) => {
    ps.once("error", () => resolvePromise(1));
    ps.once("close", resolvePromise);
  });
  if (code !== 0) return [];
  return output.split(/\r?\n/).flatMap((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.+)$/);
    return match
      ? [{ pid: Number(match[1]), ppid: Number(match[2]), identity: match[3] }]
      : [];
  });
}

function terminateInteractive(child, tree) {
  return (tree.termination ??= terminateInteractiveTree(child, tree));
}

async function terminateInteractiveTree(child, tree) {
  clearInterval(tree.poll);
  const initial = await tree.snapshot();
  const signalKnown = (signal, state) => {
    for (const pid of state.known) {
      const row = state.byPid.get(pid);
      if (
        pid !== child.pid &&
        row &&
        tree.identities.get(pid) === row.identity
      ) {
        try {
          process.kill(pid, signal);
        } catch {}
      }
    }
  };
  signalKnown("SIGTERM", initial);
  if (child.exitCode === null && child.signalCode === null) {
    try {
      child.kill("SIGTERM");
    } catch {}
  }
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 1500));
  const final = await tree.snapshot();
  signalKnown("SIGKILL", final);
  if (child.exitCode === null && child.signalCode === null) {
    try {
      child.kill("SIGKILL");
    } catch {}
  }
  // Keep ownership cleanup idempotent; completed handles are removed here.
  child.interactiveTree = null;
}

export async function configFrom(env, filename = resolve(repo, ".env")) {
  let file = "";
  try {
    file = await readFile(filename, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT")
      throw new Error("configuration: cannot read .env");
  }
  let values;
  try {
    values = parseEnv(file);
  } catch {
    throw new Error("configuration: invalid .env format");
  }
  return validate({ ...values, ...env });
}
export async function pickGatewayEnv(directory = repo) {
  const local = resolve(directory, "docker/hapi-fhir/gateway.env.local");
  try {
    await access(local);
    return "docker/hapi-fhir/gateway.env.local";
  } catch {
    return "docker/hapi-fhir/gateway.env.example";
  }
}
async function probe(url, key, fetcher) {
  try {
    const response = await fetcher(url, {
      headers: { apikey: key },
      signal: AbortSignal.timeout(3000),
    });
    const body = await response.json();
    return response.status === 405 && body?.error === "method_not_allowed";
  } catch {
    return false;
  }
}
async function networkState(run) {
  const names = await run("docker", ["ps", "-a", "--format", "{{.Names}}"]);
  if (!names.split(/\r?\n/).includes(HAPI)) return "missing";
  const networks = JSON.parse(
    await run("docker", [
      "inspect",
      HAPI,
      "--format",
      "{{json .NetworkSettings.Networks}}",
    ]),
  );
  const listed = await run("docker", [
    "network",
    "ls",
    "--no-trunc",
    "--format",
    "{{json .}}",
  ]);
  let records;
  try {
    records = listed
      .split(/\r?\n/)
      .filter(Boolean)
      .map((line) => JSON.parse(line));
  } catch {
    throw new Error("HAPI network: Docker returned invalid network metadata");
  }
  const known = new Map(records.map((item) => [item.Name, item.ID]));
  for (const [name, attached] of Object.entries(networks)) {
    if (!known.has(name) || known.get(name) !== attached.NetworkID)
      return "stale";
  }
  return Object.hasOwn(networks, NETWORK) ? "attached" : "clean";
}

export function hasPersistentHapiData(mounts, datasource) {
  return datasource === "true" && Array.isArray(mounts) && mounts.some((mount) =>
    mount.Destination === "/data/hapi" && mount.Type === "volume" &&
    mount.Name === "carer-record-hapi-data",
  );
}

export async function runApp({
  args = [],
  env = process.env,
  runner,
  fetcher = fetch,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  platform = process.platform,
  now = () => new Date(),
  onSignal = true,
  environmentOnly = false,
  signal,
} = {}) {
  const processes = runner ?? createRunner({ env, platform });
  const { run, cleanup } = processes;
  const start = processes.start ?? run;
  const controller = new AbortController();
  const externalAbort = () => { signalCode = 130; controller.abort(); };
  if (signal?.aborted) controller.abort();
  else signal?.addEventListener("abort", externalAbort, { once: true });
  let gatewayProcess;
  let failureCode = 0;
  let signalCode = 0;
  const interrupt = (signal) => {
    signalCode = signal === "SIGINT" ? 130 : 143;
    controller.abort();
    void cleanup();
  };
  const onInt = () => interrupt("SIGINT");
  const onTerm = () => interrupt("SIGTERM");
  if (onSignal) {
    process.once("SIGINT", onInt);
    process.once("SIGTERM", onTerm);
  }
  const stage = async (label, name, argv, options = {}) => {
    if (controller.signal.aborted) throw new Error("startup cancelled");
    const handle = run(name, argv, {
      stage: label,
      ...options,
      signal: controller.signal,
    });
    const status = handle?.done
      ? await Promise.race([
          handle.done,
          ...(label === "Flutter" && gatewayProcess
            ? [
                gatewayProcess.done.then(() => {
                  throw new StageFailure(
                    "gateway",
                    "process exited while Flutter was running",
                  );
                }),
              ]
            : []),
        ])
      : { code: 0, output: await handle };
    if (controller.signal.aborted) throw new Error("startup cancelled");
    if (status.reason) throw new StageFailure(label, status.reason);
    if (status.timedOut) throw new StageFailure(label, "timed out");
    if (status.code !== 0)
      throw new StageFailure(
        label,
        status.signal
          ? "terminated"
          : failureReason(status.stderr, status.code),
        status.code,
      );
    return status.output;
  };
  try {
    if (args[0] === "--gateway-only")
      throw new Error("app:run is Flutter-only; use `pnpm env:up` to start services and the gateway");
    const config = await configFrom(env);
    const childEnv = { ...process.env, ...config };
    const preflight = async (label, name, argv, cwd = repo, options = {}) =>
      stage(label, name, argv, { cwd, env: childEnv, ...options });
    if (environmentOnly) {
      for (const [name, argv] of [["docker", ["compose", "version"]], ["pnpm", ["--version"]], ["pnpm", ["exec", "supabase", "--version"]]])
        await preflight(`preflight ${name}`, name, argv);
      await preflight("preflight Docker daemon", "docker", ["info"]);
      await preflight("Supabase startup", "pnpm", ["exec", "supabase", "start"]);
    } else {
      const gatewayUrl = `${config.SUPABASE_LOCAL_URL.replace(/\/$/, "")}/functions/v1/clinical-record`;
      if (!(await probe(gatewayUrl, config.SUPABASE_PUBLISHABLE_KEY, fetcher)))
        throw new Error("gateway readiness: unavailable; run `pnpm env:up` in another terminal first");
      buildInvocation("fvm", ["flutter", "run", ...args, `--dart-define=SUPABASE_URL=${config.SUPABASE_URL}`, `--dart-define=SUPABASE_PUBLISHABLE_KEY=${config.SUPABASE_PUBLISHABLE_KEY}`], platform, { ...process.env, ...config });
      await preflight("preflight fvm flutter", "fvm", ["flutter", "--version"], resolve(repo, "app"));
      const flutterArgs = ["flutter", "run", `--dart-define=SUPABASE_URL=${config.SUPABASE_URL}`, `--dart-define=SUPABASE_PUBLISHABLE_KEY=${config.SUPABASE_PUBLISHABLE_KEY}`, `--dart-define=FHIR_BASE_URL=http://127.0.0.1:${config.HAPI_FHIR_PORT}/fhir`, ...args.filter((arg, index) => !(index === 0 && arg === "--"))];
      await stage("Flutter", "fvm", flutterArgs, { cwd: resolve(repo, "app"), env: { ...process.env, ...config }, interactive: true });
      return 0;
    }
    const prior = await networkState((name, argv) =>
      preflight("HAPI network inspect", name, argv),
    );
    if (prior !== "missing") {
      const mounts = await preflight("HAPI persistence inspect", "docker", [
        "inspect", HAPI, "--format", "{{json .Mounts}}",
      ]);
      const datasource = await preflight("HAPI datasource inspect", "docker", [
        "inspect", HAPI, "--format",
        '{{range .Config.Env}}{{if eq . "SPRING_DATASOURCE_URL=jdbc:h2:file:/data/hapi/hapi;DB_CLOSE_ON_EXIT=FALSE"}}true{{end}}{{end}}',
      ]);
      let parsed;
      try { parsed = JSON.parse(mounts); } catch { throw new Error("HAPI persistence: invalid Docker mount metadata; refusing startup"); }
      if (!hasPersistentHapiData(parsed, datasource.trim()))
        throw new Error("HAPI persistence: existing container does not have the expected persistent H2 datasource and /data/hapi volume. Refusing to start, stop, delete, or recreate it because its dataset cannot be recovered safely. Export synthetic data with `node scripts/fhir-sync/hapi-data-transfer.mjs export --confirm-synthetic` before any manual transition; then follow the restore instructions in docker/hapi-fhir/README.md.");
    }
    if (prior === "stale")
      throw new Error(
        "HAPI network: attached to an obsolete Docker network; do not stop/delete/recreate HAPI. Export the synthetic dataset first with `node scripts/fhir-sync/hapi-data-transfer.mjs export --confirm-synthetic`, then follow docker/hapi-fhir/README.md for the guarded network transition.",
      );
    await preflight("HAPI startup", "docker", [
      "compose",
      "-f",
      composeFile,
      "up",
      "-d",
      "hapi-fhir",
    ]);
    const fhir = `http://127.0.0.1:${config.HAPI_FHIR_PORT}/fhir`;
    await preflight("HAPI seed", process.execPath, [resolve(root, "fhir-sync/bootstrap-demo.mjs")], repo, { env: { ...childEnv, FHIR_BASE_URL: fhir } });
    const institutionTimezone = "America/Santiago";
    const dailyEnv = { ...childEnv, FHIR_BASE_URL: fhir, FHIR_DEMO_TIMEZONE: institutionTimezone };
    const dailyDay = () => new Intl.DateTimeFormat("en-CA", { timeZone: institutionTimezone, year: "numeric", month: "2-digit", day: "2-digit" }).format(now());
    const seededDay = dailyDay();
    const runDaily = () => preflight("daily synthetic events", process.execPath, [resolve(root, "fhir-sync/ensure-demo-current-events.mjs")], repo, { env: dailyEnv });
    await runDaily();
    await preflight("FHIR sync", process.execPath, [
      resolve(root, "fhir-sync/generate-sync.mjs"),
      "--apply",
      fhir,
    ]);
    await preflight("demo assignments", process.execPath, [
      resolve(root, "fhir-sync/generate-sync.mjs"),
      "--demo-assignments",
    ]);
    const attached = await preflight("HAPI network check", "docker", [
      "network",
      "inspect",
      NETWORK,
      "--format",
      '{{range .Containers}}{{.Name}}{{"\\n"}}{{end}}',
    ]);
    if (!attached.includes(HAPI))
      await preflight("HAPI network attach", "docker", [
        "network",
        "connect",
        "--alias",
        "hapi-fhir",
        NETWORK,
        HAPI,
      ]);
    const gatewayUrl = `${config.SUPABASE_LOCAL_URL.replace(/\/$/, "")}/functions/v1/clinical-record`;
    gatewayProcess = start(
      "pnpm",
      [
        "exec",
        "supabase",
        "functions",
        "serve",
        // Serves every function: clinical-record and clinical-attachment (ADR-022).
        "--env-file",
        await pickGatewayEnv(),
      ],
      {
        env: childEnv,
        signal: controller.signal,
        stage: "gateway serve",
        timeout: 0,
      },
    );
    let gatewayStatus;
    gatewayProcess?.done.then((status) => {
      gatewayStatus = status;
    });
    let ready = false;
    for (let i = 0; i < 60; i++) {
      if (controller.signal.aborted) throw new Error("startup cancelled");
      if (gatewayProcess) {
        if (gatewayStatus)
          throw new Error("gateway startup: process exited early");
      }
      if (await probe(gatewayUrl, config.SUPABASE_PUBLISHABLE_KEY, fetcher)) {
        ready = true;
        break;
      }
      await sleep(2000);
    }
    if (!ready) throw new Error("gateway readiness: timed out");
    if (dailyDay() !== seededDay) {
      const retryDay = dailyDay();
      await runDaily();
      if (dailyDay() !== retryDay)
        throw new Error("daily synthetic events: institutional day changed repeatedly during startup");
    }
    if (environmentOnly) {
      console.log("Environment ready. Ctrl+C stops the gateway only; containers remain running.");
      let failedProbes = 0;
      while (!controller.signal.aborted) {
        if (gatewayStatus) {
          let runtimeAvailable = false;
          try {
            const response = await fetcher(`${config.SUPABASE_LOCAL_URL.replace(/\/$/, "")}/rest/v1/`, { headers: { apikey: config.SUPABASE_PUBLISHABLE_KEY }, signal: AbortSignal.timeout(3000) });
            runtimeAvailable = response.status > 0;
          } catch {}
          if (runtimeAvailable)
            throw new StageFailure("gateway", "process exited unexpectedly", gatewayStatus.code ?? 1);
          console.error("Supabase runtime is unavailable; env:stop has stopped services.");
          break;
        }
        const gatewayReady = await probe(gatewayUrl, config.SUPABASE_PUBLISHABLE_KEY, fetcher);
        failedProbes = gatewayReady ? 0 : failedProbes + 1;
        if (failedProbes >= 3) {
          let runtimeAvailable = false;
          try {
            const response = await fetcher(`${config.SUPABASE_LOCAL_URL.replace(/\/$/, "")}/rest/v1/`, { headers: { apikey: config.SUPABASE_PUBLISHABLE_KEY }, signal: AbortSignal.timeout(3000) });
            runtimeAvailable = response.status > 0;
          } catch {}
          if (runtimeAvailable) {
            throw new StageFailure("gateway", "unhealthy while Supabase remains available", 1);
          }
          console.error("Supabase runtime is unavailable; stopping only env:up's gateway process.");
          break;
        }
        await sleep(2000);
      }
    }
  } catch (error) {
    if (!controller.signal.aborted)
      console.error(
        `[${error.stage ?? error.message.split(":")[0]}] ${error.reason ?? (error.message.includes(":") ? error.message.slice(error.message.indexOf(":") + 1).trim() : "startup failed")}`,
      );
    failureCode = error.exitCode || 1;
  } finally {
    if (gatewayProcess) await gatewayProcess.stop();
    await cleanup();
    if (onSignal) {
      process.removeListener("SIGINT", onInt);
      process.removeListener("SIGTERM", onTerm);
    }
    signal?.removeEventListener("abort", externalAbort);
  }
  return signalCode || (controller.signal.aborted ? 1 : failureCode);
}

class StageFailure extends Error {
  constructor(stage, reason, exitCode) {
    super(`${stage}: ${reason}`);
    this.stage = stage;
    this.reason = reason;
    this.exitCode = exitCode;
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
)
  process.exitCode = await runApp({ args: process.argv.slice(2) });
