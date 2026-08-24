#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { validateOfficialReleaseFeed } from "../site/release-data.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultFeedPath = path.join(repositoryRoot, "site/official-app-releases.json");

export function canonicalJSON(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function contentReceipt(feed) {
  const receipted = {
    latest: feed.latest,
    releases: feed.releases,
    schemaVersion: feed.schemaVersion,
    source: feed.source,
    updatedAt: feed.updatedAt,
  };
  return crypto.createHash("sha256").update(canonicalJSON(receipted)).digest("hex");
}

export function verifyFeed(feed) {
  validateOfficialReleaseFeed(feed);
  const userContent = feed.releases.flatMap((release) => [
    ...Object.values(release.title),
    ...Object.values(release.summary),
    ...release.highlights.flatMap(Object.values),
  ]).join("\n");
  if (/(?:scripts?\/|\.sh\b|sha-?256|appcast|notari[sz]|candidate|release gate|receipt|commit\s+[0-9a-f]{7,})/i.test(userContent)) {
    throw new Error("official release feed contains internal delivery detail");
  }
  const actualReceipt = contentReceipt(feed);
  if (feed.contentReceiptSHA256 !== actualReceipt) {
    throw new Error("official release feed content receipt does not match");
  }
  return feed;
}

export function verifySourceReceipt(feed, sourceReceipt) {
  const expectedReceiptKeys = ["channel", "contentReceiptSHA256", "latest", "schemaVersion", "updatedAt"];
  if (JSON.stringify(Object.keys(sourceReceipt).sort()) !== JSON.stringify(expectedReceiptKeys.sort())
    || sourceReceipt.schemaVersion !== 1
    || sourceReceipt.channel !== feed.source.channel
    || sourceReceipt.contentReceiptSHA256 !== feed.contentReceiptSHA256
    || sourceReceipt.latest !== feed.latest
    || sourceReceipt.updatedAt !== feed.updatedAt) {
    throw new Error("official release source receipt does not match the feed");
  }
  return sourceReceipt;
}

export function verifyFeedFile(feedPath) {
  const bytes = fs.readFileSync(feedPath);
  const feed = verifyFeed(JSON.parse(bytes.toString("utf8")));
  const sidecarPath = `${feedPath}.sha256`;
  const sidecar = fs.readFileSync(sidecarPath, "utf8");
  const expectedSidecar = `${crypto.createHash("sha256").update(bytes).digest("hex")}  ${path.basename(feedPath)}\n`;
  if (sidecar !== expectedSidecar) {
    throw new Error("official release feed digest sidecar does not match");
  }
  const sourceReceiptPath = path.join(path.dirname(feedPath), feed.source.receipt);
  const sourceReceiptBytes = fs.readFileSync(sourceReceiptPath);
  const sourceReceipt = JSON.parse(sourceReceiptBytes.toString("utf8"));
  verifySourceReceipt(feed, sourceReceipt);
  const sourceSidecar = fs.readFileSync(`${sourceReceiptPath}.sha256`, "utf8");
  const expectedSourceSidecar = `${crypto.createHash("sha256").update(sourceReceiptBytes).digest("hex")}  ${path.basename(sourceReceiptPath)}\n`;
  if (sourceSidecar !== expectedSourceSidecar) {
    throw new Error("official release source receipt digest sidecar does not match");
  }
  return feed;
}

function run() {
  const feedPath = process.argv[2] ? path.resolve(process.argv[2]) : defaultFeedPath;
  try {
    const feed = verifyFeedFile(feedPath);
    console.log(`verify-official-release-feed: ${feed.releases.length} official App releases passed`);
  } catch (error) {
    console.error(`verify-official-release-feed: ${error.message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) run();
