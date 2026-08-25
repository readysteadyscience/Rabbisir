#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  contentReceipt,
  verifyFeed,
  verifyFeedFile,
} from "./verify-official-release-feed.mjs";

const releaseTypeContent = {
  feature: {
    highlights: [{ en: "Introduces verified user-facing additions.", zh: "带来已验证的用户功能更新。" }],
    summary: {
      en: "A feature release with verified additions for Rabbisir users.",
      zh: "一次面向 Rabbisir 用户、包含已验证新增功能的版本更新。",
    },
    title: { en: "Feature update", zh: "功能更新" },
  },
  fix: {
    highlights: [{ en: "Resolves verified issues from the previous version.", zh: "修复上一版本中已确认的问题。" }],
    summary: {
      en: "This release contains verified fixes for a more reliable everyday experience.",
      zh: "本次版本包含已验证的修复，提升日常使用可靠性。",
    },
    title: { en: "Fixes", zh: "修复" },
  },
  optimization: {
    highlights: [{ en: "Includes verified improvements to the everyday experience.", zh: "包含已验证的日常体验改进。" }],
    summary: {
      en: "An optimization release focused on a smoother Rabbisir experience.",
      zh: "一次聚焦 Rabbisir 使用体验的优化版本。",
    },
    title: { en: "Optimization", zh: "优化" },
  },
};

function canonicalVersion(version) {
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) {
    throw new Error("official App release version must be canonical three-part SemVer");
  }
  return `Rabbisir ${version}`;
}

function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().startsWith(value);
}

function jsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

function sidecarBytes(bytes, filename) {
  const digest = crypto.createHash("sha256").update(bytes).digest("hex");
  return Buffer.from(`${digest}  ${filename}\n`);
}

function sameJSON(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

export function releaseRecord(version, publishedOn, releaseType) {
  if (!validDate(publishedOn)) throw new Error("official App release date must use a real YYYY-MM-DD date");
  const content = releaseTypeContent[releaseType];
  if (!content) throw new Error("official App release type is unsupported");
  return {
    version: canonicalVersion(version),
    publishedOn,
    title: content.title,
    summary: content.summary,
    highlights: content.highlights,
  };
}

export function updatedFeed(existingFeed, version, publishedOn, releaseType) {
  const entry = releaseRecord(version, publishedOn, releaseType);
  const existingIndex = existingFeed.releases.findIndex((release) => release.version === entry.version);
  if (existingIndex >= 0 && !sameJSON(existingFeed.releases[existingIndex], entry)) {
    throw new Error("official App release history already contains different content for this version");
  }
  const releases = existingIndex >= 0
    ? [entry, ...existingFeed.releases.filter((_release, index) => index !== existingIndex)]
    : [entry, ...existingFeed.releases];
  const feed = {
    schemaVersion: 1,
    updatedAt: `${publishedOn}T00:00:00Z`,
    latest: entry.version,
    contentReceiptSHA256: "0".repeat(64),
    source: {
      channel: "rabbisir-official-app",
      receipt: "official-app-release-source.json",
    },
    releases,
  };
  feed.contentReceiptSHA256 = contentReceipt(feed);
  return verifyFeed(feed);
}

export function updateFeedFiles(feedPath, version, publishedOn, releaseType) {
  const resolvedFeedPath = path.resolve(feedPath);
  const existingFeed = verifyFeedFile(resolvedFeedPath);
  const feed = updatedFeed(existingFeed, version, publishedOn, releaseType);
  const source = {
    schemaVersion: 1,
    channel: feed.source.channel,
    updatedAt: feed.updatedAt,
    latest: feed.latest,
    contentReceiptSHA256: feed.contentReceiptSHA256,
  };
  const feedName = path.basename(resolvedFeedPath);
  const sourceName = feed.source.receipt;
  const feedBytes = jsonBytes(feed);
  const sourceBytes = jsonBytes(source);
  const stagingRoot = fs.mkdtempSync(path.join(os.tmpdir(), "rabbisir-official-release-feed."));
  try {
    const stagedFeedPath = path.join(stagingRoot, feedName);
    const stagedSourcePath = path.join(stagingRoot, sourceName);
    fs.writeFileSync(stagedFeedPath, feedBytes);
    fs.writeFileSync(`${stagedFeedPath}.sha256`, sidecarBytes(feedBytes, feedName));
    fs.writeFileSync(stagedSourcePath, sourceBytes);
    fs.writeFileSync(`${stagedSourcePath}.sha256`, sidecarBytes(sourceBytes, sourceName));
    verifyFeedFile(stagedFeedPath);
    for (const name of [feedName, `${feedName}.sha256`, sourceName, `${sourceName}.sha256`]) {
      fs.renameSync(path.join(stagingRoot, name), path.join(path.dirname(resolvedFeedPath), name));
    }
    return verifyFeedFile(resolvedFeedPath);
  } finally {
    fs.rmSync(stagingRoot, { force: true, recursive: true });
  }
}

function run() {
  const [feedPath, version, publishedOn, releaseType] = process.argv.slice(2);
  if (!feedPath || !version || !publishedOn || !releaseType || process.argv.length !== 6) {
    console.error("usage: update-official-release-feed.mjs <feed> <version> <YYYY-MM-DD> <feature|fix|optimization>");
    process.exit(64);
  }
  try {
    const feed = updateFeedFiles(feedPath, version, publishedOn, releaseType);
    console.log(`update-official-release-feed: ${feed.latest} prepared with ${feed.releases.length} history entries`);
  } catch (error) {
    console.error(`update-official-release-feed: ${error.message}`);
    process.exit(1);
  }
}

let isMainModule = false;
if (process.argv[1]) {
  try {
    isMainModule = fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    // A missing or unreadable entry point is not this CLI.
  }
}
if (isMainModule) run();
