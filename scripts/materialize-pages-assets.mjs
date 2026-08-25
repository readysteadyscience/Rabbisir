#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import https from "node:https";
import path from "node:path";

const fail = (message) => {
  process.stderr.write(`materialize-pages-assets: ${message}\n`);
  process.exit(1);
};
const exactKeys = (value, keys) => value && typeof value === "object" && !Array.isArray(value)
  && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());
const allowedRedirectHost = (hostname) => hostname === "github.com"
  || hostname === "objects.githubusercontent.com"
  || hostname.endsWith(".githubusercontent.com");

const [command, manifestInput, siteInput, localSourceInput] = process.argv.slice(2);
if (!["verify-source", "materialize", "materialize-local"].includes(command)
  || !manifestInput || !siteInput
  || (command === "materialize-local") !== Boolean(localSourceInput)) {
  fail("usage: materialize-pages-assets.mjs verify-source|materialize <manifest> <site-root> | materialize-local <manifest> <site-root> <source-root>");
}

const manifestPath = path.resolve(manifestInput);
const siteRoot = path.resolve(siteInput);
let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
} catch {
  fail("the Pages source manifest is unreadable");
}
if (!exactKeys(manifest, ["deploymentAssets", "files", "provenance", "publicAppcastURL", "publicBase", "releaseTag", "runtime", "schemaVersion", "verification", "workflow"])
  || manifest.schemaVersion !== 4
  || !Array.isArray(manifest.deploymentAssets)
  || manifest.deploymentAssets.length !== 1) {
  fail("the Pages source manifest does not declare one schema 4 deployment asset");
}
const asset = manifest.deploymentAssets[0];
if (!exactKeys(asset, ["name", "sha256", "size", "sourceURL"])
  || asset.name !== "Rabbisir.dmg"
  || !/^[0-9a-f]{64}$/.test(asset.sha256 || "")
  || !Number.isSafeInteger(asset.size) || asset.size < 1
  || manifest.files?.some((entry) => entry?.name === asset.name)) {
  fail("the stable DMG deployment record is invalid or entered the Git file closure");
}
let sourceURL;
try {
  sourceURL = new URL(asset.sourceURL);
} catch {
  fail("the stable DMG source URL is invalid");
}
const expectedPrefix = `/readysteadyscience/Rabbisir/releases/download/${manifest.releaseTag}/`;
if (sourceURL.protocol !== "https:" || sourceURL.hostname !== "github.com"
  || !sourceURL.pathname.startsWith(expectedPrefix)
  || !/^Rabbisir-[0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*\.dmg$/.test(path.basename(sourceURL.pathname))) {
  fail("the stable DMG source is not the frozen versioned GitHub Release asset");
}
const destination = path.join(siteRoot, asset.name);
if (command === "verify-source") {
  if (fs.existsSync(destination)) fail("the stable DMG must not exist in the Git source tree");
  process.stdout.write("materialize-pages-assets: schema 4 source keeps the stable DMG outside Git history\n");
  process.exit(0);
}
if (!fs.statSync(siteRoot, { throwIfNoEntry: false })?.isDirectory() || fs.existsSync(destination)) {
  fail("the Pages site root must exist without a stable DMG");
}

const temporary = path.join(siteRoot, `.${asset.name}.tmp-${process.pid}`);
const cleanup = () => fs.rmSync(temporary, { force: true });
const verifiedWrite = (readable) => new Promise((resolve, reject) => {
  const digest = crypto.createHash("sha256");
  let size = 0;
  const output = fs.createWriteStream(temporary, { flags: "wx", mode: 0o644 });
  const stop = (error) => {
    readable.destroy();
    output.destroy();
    reject(error);
  };
  readable.on("data", (chunk) => {
    size += chunk.length;
    if (size > asset.size) stop(new Error("the downloaded stable DMG exceeds its frozen size"));
    else digest.update(chunk);
  });
  readable.on("error", stop);
  output.on("error", stop);
  output.on("finish", () => {
    if (size !== asset.size || digest.digest("hex") !== asset.sha256) {
      reject(new Error("the downloaded stable DMG differs from its frozen size or SHA-256"));
    } else resolve();
  });
  readable.pipe(output);
});
const download = (url, redirects = 0) => new Promise((resolve, reject) => {
  if (redirects > 5 || url.protocol !== "https:" || !allowedRedirectHost(url.hostname)) {
    reject(new Error("the stable DMG redirect chain is not allowed"));
    return;
  }
  https.get(url, { headers: { "User-Agent": "Rabbisir-Pages-Materializer/1" } }, (response) => {
    if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
      response.resume();
      download(new URL(response.headers.location, url), redirects + 1).then(resolve, reject);
    } else if (response.statusCode === 200) {
      resolve(response);
    } else {
      response.resume();
      reject(new Error(`the stable DMG request failed with HTTP ${response.statusCode}`));
    }
  }).on("error", reject);
});

try {
  const input = command === "materialize-local"
    ? fs.createReadStream(path.join(path.resolve(localSourceInput), path.basename(sourceURL.pathname)))
    : await download(sourceURL);
  await verifiedWrite(input);
  fs.renameSync(temporary, destination);
} catch (error) {
  cleanup();
  fail(error instanceof Error ? error.message : "the stable DMG could not be materialized");
}
process.stdout.write("materialize-pages-assets: stable DMG materialized from its frozen Release record\n");
