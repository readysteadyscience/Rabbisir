#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  cacheIsFresh,
  createReleaseDetailsController,
  fallbackFeedURL,
  feedURL,
  latestDownloadURL,
  formattedReleaseDate,
} from "../site/release-details.mjs";
import {
  mergeNormalizedReleaseFeeds,
  normalizeOfficialReleaseFeed,
  validateOfficialReleaseFeed,
} from "../site/release-data.mjs";
import {
  contentReceipt,
  verifyFeed,
  verifyFeedFile,
  verifySourceReceipt,
} from "./verify-official-release-feed.mjs";
import { releaseRecord, updatedFeed } from "./update-official-release-feed.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const feedPath = path.join(repositoryRoot, "site/official-app-releases.json");
const feed = JSON.parse(fs.readFileSync(feedPath, "utf8"));
const sourceReceipt = JSON.parse(fs.readFileSync(path.join(repositoryRoot, "site/official-app-release-source.json"), "utf8"));
const authorityFeed = {
  $schema: "./official-app-releases.schema.json",
  schemaVersion: 2,
  channel: "production",
  updatedAt: "2026-08-26T04:17:51Z",
  authority: {
    repository: "readysteadyscience/Rabbisir-Releases",
    appcastURL: "https://raw.githubusercontent.com/readysteadyscience/Rabbisir-Releases/main/appcast.xml",
    stableDownloadURL: "https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg",
  },
  latest: { version: "0.1.4", build: "6", tag: "v0.1.4" },
  releases: [{
    version: "0.1.4",
    build: "6",
    tag: "v0.1.4",
    publishedOn: "2026-08-26",
    selectedTypes: ["feature", "optimization", "fix"],
    categories: {
      feature: [{ en: "Adds a verified user-facing capability.", zh: "新增一项已验证的用户功能。" }],
      optimization: [{ en: "Improves a verified everyday workflow.", zh: "改进一项已验证的日常流程。" }],
      fix: [{ en: "Resolves a verified issue from the previous version.", zh: "修复上一版本中一项已确认的问题。" }],
    },
    releaseURL: "https://github.com/readysteadyscience/Rabbisir-Releases/releases/tag/v0.1.4",
    assets: [
      { name: "Rabbisir-0.1.4-6.zip", url: "https://github.com/readysteadyscience/Rabbisir-Releases/releases/download/v0.1.4/Rabbisir-0.1.4-6.zip", size: 100, sha256: "a".repeat(64) },
      { name: "Rabbisir-0.1.4-6.dmg", url: "https://github.com/readysteadyscience/Rabbisir-Releases/releases/download/v0.1.4/Rabbisir-0.1.4-6.dmg", size: 200, sha256: "b".repeat(64) },
      { name: "Rabbisir.dmg", url: "https://github.com/readysteadyscience/Rabbisir-Releases/releases/download/v0.1.4/Rabbisir.dmg", size: 200, sha256: "b".repeat(64) },
    ],
  }],
};

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function resign(value) {
  value.contentReceiptSHA256 = contentReceipt(value);
  return value;
}

class FakeNode {
  constructor(name) {
    this.name = name;
    this.children = [];
    this.attributes = new Map();
    this.className = "";
    this.dateTime = "";
    this.value = "";
  }

  set textContent(value) {
    this.value = String(value);
    this.children = [];
  }

  get textContent() {
    return `${this.value}${this.children.map((child) => child.textContent).join("")}`;
  }

  set innerHTML(_value) {
    throw new Error("release rendering must not use innerHTML");
  }

  append(...nodes) {
    nodes.forEach((node) => {
      if (node.name === "#fragment") this.children.push(...node.children);
      else this.children.push(node);
    });
  }

  replaceChildren(...nodes) {
    this.children = [];
    this.value = "";
    this.append(...nodes);
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }
}

function createFakeDocument(language = "en") {
  const list = new FakeNode("div");
  list.setAttribute("aria-busy", "true");
  const status = new FakeNode("p");
  status.textContent = "Loading official release information…";
  const nodes = new Map([
    ["#release-list", list],
    ["#release-feed-status", status],
  ]);
  return {
    createDocumentFragment: () => new FakeNode("#fragment"),
    createElement: (name) => new FakeNode(name),
    documentElement: { lang: language },
    querySelector: (selector) => nodes.get(selector) ?? null,
    list,
    status,
  };
}

function createStorage(cachedValue = null) {
  const values = new Map();
  if (cachedValue !== null) values.set("rabbisir-official-app-releases-v2", JSON.stringify(cachedValue));
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    values,
  };
}

function controllerFor({ documentObject, fetchFunction, storage, now = () => 1_000_000, timeoutMilliseconds = 25 }) {
  return createReleaseDetailsController({
    documentObject,
    fetchFunction,
    storage,
    now,
    timeoutMilliseconds,
  });
}

verifyFeedFile(feedPath);
assert.equal(validateOfficialReleaseFeed(feed), feed);
assert.equal(validateOfficialReleaseFeed(authorityFeed), authorityFeed);
assert.equal(verifySourceReceipt(feed, sourceReceipt), sourceReceipt);
assert.match(feed.latest, /^Rabbisir \d+\.\d+\.\d+$/);
assert.equal(feed.releases.some((release) => / · r\d+\.\d{2}$/.test(release.version)), true);
assert.equal(formattedReleaseDate("2026-08-20", "en"), "August 20, 2026");
assert.equal(formattedReleaseDate("2026-08-20", "zh"), "2026年8月20日");
assert.equal(cacheIsFresh(1_000, 1_000 + 299_999), true);
assert.equal(cacheIsFresh(1_000, 1_000 + 300_000), false);
assert.equal(latestDownloadURL, "https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg");

const normalizedAuthorityFeed = normalizeOfficialReleaseFeed(authorityFeed);
const normalizedBundledFeed = normalizeOfficialReleaseFeed(feed);
const mergedReleaseFeed = mergeNormalizedReleaseFeeds(normalizedAuthorityFeed, normalizedBundledFeed);
assert.equal(normalizedAuthorityFeed.latest, "Rabbisir 0.1.4");
assert.equal(normalizedAuthorityFeed.releases[0].build, "6");
assert.deepEqual(
  normalizedAuthorityFeed.releases[0].releaseTypes.map((type) => type.key),
  ["feature", "optimization", "fix"],
);
assert.equal(normalizedAuthorityFeed.releases[0].highlights.length, 3);
assert.equal(mergedReleaseFeed.releases.length, feed.releases.length);
assert.equal(mergedReleaseFeed.releases[0].build, "6");
assert.equal(mergedReleaseFeed.releases[1].version, "Rabbisir 0.1.2");
assert.equal(mergedReleaseFeed.releases.filter((release) => release.version === "Rabbisir 0.1.4").length, 1);

const missingSelectedCategory = clone(authorityFeed);
delete missingSelectedCategory.releases[0].categories.fix;
assert.throws(() => validateOfficialReleaseFeed(missingSelectedCategory), /categories differ/);
const unselectedCategory = clone(authorityFeed);
unselectedCategory.releases[0].selectedTypes = ["fix"];
assert.throws(() => validateOfficialReleaseFeed(unselectedCategory), /categories differ/);
const wrongAuthority = clone(authorityFeed);
wrongAuthority.authority.repository = "readysteadyscience/Rabbisir";
assert.throws(() => validateOfficialReleaseFeed(wrongAuthority), /authority differs/);
const wrongLatestBuild = clone(authorityFeed);
wrongLatestBuild.latest.build = "7";
assert.throws(() => validateOfficialReleaseFeed(wrongLatestBuild), /latest identity must match/);
const missingStableAlias = clone(authorityFeed);
missingStableAlias.releases[0].assets[2] = {
  name: "checksums.txt",
  url: "https://github.com/readysteadyscience/Rabbisir-Releases/releases/download/v0.1.4/checksums.txt",
  size: 50,
  sha256: "c".repeat(64),
};
assert.throws(() => validateOfficialReleaseFeed(missingStableAlias), /stable DMG alias/);

const forwardMajor = feed.releases.reduce((maximum, release) => {
  const match = /^Rabbisir (\d+)\.\d+\.\d+/.exec(release.version);
  assert.ok(match, "verified release versions must expose their SemVer major");
  const major = BigInt(match[1]);
  return major > maximum ? major : maximum;
}, 0n) + 1n;
const forwardVersion = `${forwardMajor}.0.0`;
const forwardDate = feed.releases[0].publishedOn;
const forwardFix = updatedFeed(feed, forwardVersion, forwardDate, "fix");
assert.equal(forwardFix.latest, `Rabbisir ${forwardVersion}`);
assert.deepEqual(forwardFix.releases[0].title, { en: "Fixes", zh: "修复" });
assert.equal(forwardFix.releases[1].version, feed.releases[0].version);
assert.throws(
  () => releaseRecord("0.1.2-r1.03", "2026-08-25", "fix"),
  /canonical three-part SemVer/
);
assert.throws(
  () => releaseRecord("0.1.2", "2026-02-30", "fix"),
  /real YYYY-MM-DD/
);
const conflictingVersion = clone(feed);
conflictingVersion.releases.unshift({
  ...releaseRecord(forwardVersion, forwardDate, "fix"),
  summary: { en: "Conflicting content", zh: "冲突内容" },
});
assert.throws(
  () => updatedFeed(conflictingVersion, forwardVersion, forwardDate, "fix"),
  /different content/
);

const mismatchedLatest = resign(clone(feed));
mismatchedLatest.latest = mismatchedLatest.releases[1].version;
assert.throws(() => verifyFeed(mismatchedLatest), /latest/);

const missingChinese = resign(clone(feed));
delete missingChinese.releases[0].summary.zh;
assert.throws(() => verifyFeed(missingChinese), /en and zh/);

const reversed = resign(clone(feed));
reversed.releases.reverse();
reversed.latest = reversed.releases[0].version;
reversed.contentReceiptSHA256 = contentReceipt(reversed);
assert.throws(() => verifyFeed(reversed), /newest first/);

const legacySuccessor = resign(clone(feed));
legacySuccessor.releases[0].version = "Rabbisir 0.1.2 · r1.03";
legacySuccessor.latest = legacySuccessor.releases[0].version;
legacySuccessor.contentReceiptSHA256 = contentReceipt(legacySuccessor);
assert.throws(() => validateOfficialReleaseFeed(legacySuccessor), /latest/);

const unboundedOutOfOrder = resign(clone(feed));
unboundedOutOfOrder.releases = [
  releaseRecord("9007199254740992.0.0", "2026-08-25", "fix"),
  releaseRecord("9007199254740993.0.0", "2026-08-25", "fix"),
  ...unboundedOutOfOrder.releases.slice(1),
];
unboundedOutOfOrder.latest = unboundedOutOfOrder.releases[0].version;
unboundedOutOfOrder.contentReceiptSHA256 = contentReceipt(unboundedOutOfOrder);
assert.throws(() => verifyFeed(unboundedOutOfOrder), /same-day official releases/);

const nonCanonicalSemver = resign(clone(feed));
nonCanonicalSemver.releases[0].version = "Rabbisir 0.01.2";
nonCanonicalSemver.latest = nonCanonicalSemver.releases[0].version;
nonCanonicalSemver.contentReceiptSHA256 = contentReceipt(nonCanonicalSemver);
assert.throws(() => verifyFeed(nonCanonicalSemver), /shape or version/);

const internalDetail = resign(clone(feed));
internalDetail.releases[0].highlights[0].en = "Updated scripts/release.sh and its release gate.";
internalDetail.contentReceiptSHA256 = contentReceipt(internalDetail);
assert.throws(() => verifyFeed(internalDetail), /internal delivery detail/);

const tampered = clone(feed);
tampered.releases[0].title.en = "Changed without updating metadata";
assert.throws(() => verifyFeed(tampered), /content receipt/);

const mismatchedSourceReceipt = clone(sourceReceipt);
mismatchedSourceReceipt.latest = feed.releases[1].version;
assert.throws(() => verifySourceReceipt(feed, mismatchedSourceReceipt), /source receipt/);

{
  const documentObject = createFakeDocument();
  const storage = createStorage({ feed: authorityFeed, history: feed, savedAt: 999_500 });
  let requestCount = 0;
  const controller = controllerFor({
    documentObject,
    fetchFunction: async () => { requestCount += 1; throw new Error("fresh cache must not fetch"); },
    storage,
  });
  assert.equal(await controller.load(), "fresh-cache");
  assert.equal(requestCount, 0);
  assert.equal(documentObject.list.children.length, mergedReleaseFeed.releases.length);
  assert.equal(documentObject.list.getAttribute("aria-busy"), "false");
  assert.equal(documentObject.status.textContent, "Official release information is up to date.");
}

{
  const documentObject = createFakeDocument();
  const storage = createStorage();
  let requestCount = 0;
  const controller = controllerFor({
    documentObject,
    fetchFunction: async (url, options) => {
      requestCount += 1;
      assert.ok(url === feedURL || url === fallbackFeedURL);
      assert.equal(options.cache, "no-cache");
      assert.equal(options.credentials, "omit");
      assert.equal(options.referrerPolicy, "no-referrer");
      return { ok: true, json: async () => clone(url === feedURL ? authorityFeed : feed) };
    },
    storage,
  });
  assert.equal(await controller.load(), "network");
  assert.equal(requestCount, 2);
  assert.match(storage.values.get("rabbisir-official-app-releases-v2"), /"schemaVersion":2/);
  assert.match(storage.values.get("rabbisir-official-app-releases-v2"), /"history"/);
  assert.equal(documentObject.list.children.length, feed.releases.length);
  assert.match(documentObject.list.textContent, /Build 6/);
  assert.match(documentObject.list.textContent, /Feature update/);
  assert.match(documentObject.list.textContent, /Capability improvements/);
  assert.match(documentObject.list.textContent, /Bug fixes/);
  assert.match(documentObject.list.textContent, /Download DMG/);
  assert.equal(documentObject.list.getAttribute("aria-busy"), "false");
}

{
  const documentObject = createFakeDocument();
  let finishRequest;
  const controller = controllerFor({
    documentObject,
    fetchFunction: (url) => url === fallbackFeedURL
      ? Promise.resolve({ ok: true, json: async () => clone(feed) })
      : new Promise((resolve) => { finishRequest = resolve; }),
    storage: createStorage(),
  });
  const loading = controller.load();
  documentObject.documentElement.lang = "zh-CN";
  controller.rerender();
  assert.equal(documentObject.status.textContent, "Loading official release information…");
  assert.equal(documentObject.list.getAttribute("aria-busy"), "true");
  finishRequest({ ok: true, json: async () => clone(authorityFeed) });
  assert.equal(await loading, "network");
}

{
  const documentObject = createFakeDocument();
  const controller = controllerFor({
    documentObject,
    fetchFunction: async () => ({ ok: false, status: 429 }),
    storage: createStorage(),
  });
  assert.equal(await controller.load(), "unavailable");
  assert.equal(documentObject.list.children.length, 1);
  assert.match(documentObject.list.textContent, /temporarily unavailable/);
  assert.equal(documentObject.status.textContent, "The official release source could not be reached.");
  assert.equal(documentObject.list.getAttribute("aria-busy"), "false");
  documentObject.documentElement.lang = "zh-CN";
  controller.rerender();
  assert.equal(documentObject.status.textContent, "暂时无法连接正式版本数据源。");
  assert.match(documentObject.list.textContent, /版本信息暂时不可用/);
}

{
  const documentObject = createFakeDocument();
  const requestedURLs = [];
  const controller = controllerFor({
    documentObject,
    fetchFunction: async (url) => {
      requestedURLs.push(url);
      if (url === feedURL) return { ok: false, status: 503 };
      assert.equal(url, fallbackFeedURL);
      return { ok: true, json: async () => clone(feed) };
    },
    storage: createStorage(),
  });
  assert.equal(await controller.load(), "bundled-fallback");
  assert.deepEqual(requestedURLs, [feedURL, fallbackFeedURL]);
  assert.equal(documentObject.list.children.length, feed.releases.length);
  assert.equal(documentObject.status.textContent, "Showing verified fallback release information while the live source is unavailable.");
}

{
  const documentObject = createFakeDocument();
  const storage = createStorage({ feed: authorityFeed, history: feed, savedAt: 1 });
  const controller = controllerFor({
    documentObject,
    fetchFunction: async () => ({ ok: false, status: 429 }),
    storage,
  });
  assert.equal(await controller.load(), "saved-fallback");
  assert.equal(documentObject.list.children.length, feed.releases.length);
  assert.equal(documentObject.status.textContent, "Showing verified fallback release information while the live source is unavailable.");
}

{
  const documentObject = createFakeDocument();
  const controller = controllerFor({
    documentObject,
    fetchFunction: (_url, { signal }) => new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(new Error("timed out")), { once: true });
    }),
    storage: createStorage(),
    timeoutMilliseconds: 1,
  });
  assert.equal(await controller.load(), "unavailable");
  assert.equal(documentObject.list.getAttribute("aria-busy"), "false");
}

{
  const documentObject = createFakeDocument();
  const controller = controllerFor({
    documentObject,
    fetchFunction: async (url) => ({
      ok: true,
      json: async () => clone(url === feedURL ? authorityFeed : feed),
    }),
    storage: createStorage(),
  });
  await controller.load();
  documentObject.documentElement.lang = "zh-CN";
  controller.rerender();
  assert.match(documentObject.list.textContent, /功能更新/);
  assert.match(documentObject.list.textContent, /能力优化/);
  assert.match(documentObject.list.textContent, /Bug 修复/);
  assert.equal(documentObject.status.textContent, "正式版本信息已更新。");
}

console.log("test-official-release-feed: schema, receipt, network, timeout, cache, fallback, rendering, language, and accessibility tests passed");
