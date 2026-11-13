import { pathToFileURL } from "node:url";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRunner } from "./run-app.mjs";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const compose = resolve(repo, "docker/hapi-fhir/docker-compose.yml");
const container = "carer-record-hapi-fhir";
const volume = "carer-record-hapi-data";
async function command(file, args) {
  const handle = createRunner({ cwd: repo }).run(file, args, { timeout: 60_000, stage: "env:stop" });
  const status = await handle.done;
  if (status.code !== 0) throw new Error(status.stderr || `${file} exited ${status.code}`);
  return status.output;
}

export async function stopEnvironment({ run = command } = {}) {
  const names = await run("docker", ["ps", "-a", "--format", "{{.Names}}"]);
  if (names.split(/\r?\n/).includes(container)) {
    const mounts = JSON.parse(await run("docker", ["inspect", container, "--format", "{{json .Mounts}}"]));
    const datasource = await run("docker", ["inspect", container, "--format", '{{range .Config.Env}}{{if eq . "SPRING_DATASOURCE_URL=jdbc:h2:file:/data/hapi/hapi;DB_CLOSE_ON_EXIT=FALSE"}}true{{end}}{{end}}']);
    const safe = mounts.some((m) => m.Type === "volume" && m.Name === volume && m.Destination === "/data/hapi") && datasource.trim() === "true";
    if (!safe) throw new Error("Refusing to stop HAPI: expected persistent H2 datasource and carer-record-hapi-data volume were not verified. No container was changed.");
    const inspect = await run("docker", ["inspect", container, "--format", "{{json .NetworkSettings.Networks}}"]);
    const networks = JSON.parse(inspect);
    const supabase = networks["supabase_network_carer-record"];
    if (supabase) await run("docker", ["network", "disconnect", "supabase_network_carer-record", container]);
    await run("docker", ["compose", "-f", compose, "stop", "hapi-fhir"]);
  }
  await run("pnpm", ["exec", "supabase", "stop"]);
  console.log("Services stopped; data volumes preserved. env:up should exit after Supabase becomes unavailable.");
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href)
  stopEnvironment().catch((error) => { console.error(error.message); process.exitCode = 1; });
