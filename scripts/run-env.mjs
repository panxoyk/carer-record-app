import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { runApp } from "./run-app.mjs";

export const runEnvironment = (options = {}) => runApp({ ...options, environmentOnly: true });

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href)
  process.exitCode = await runEnvironment();
