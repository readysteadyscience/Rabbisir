#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { cacheIsFresh, createReleaseDetailsController, formattedReleaseDate } from "../site/release-details.mjs";
import { validateOfficialReleaseFeed } from "../site/release-data.mjs";
import {
  contentReceipt,
  verifyFeed,
  verifyFeedFile,
  verifySourceReceipt,
} from "./verify-official-release-feed.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const feedPath = path.join(repositoryRoot, "site/official-app-releases.json");
const feed = JSON.parse(fs.readFileSync(feedPath, "utf8"));
const sourceReceipt = JSON.parse(fs.readFileSync(path.join(repositoryRoot, "site/official-app-release-source.json"), "utf8"));

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
  if (cachedValue !== null) values.set("rabbisir-official-app-releases-v1", JSON.stringify(cachedValue));
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
assert.equal(verifySourceReceipt(feed, sourceReceipt), sourceReceipt);
assert.equal(formattedReleaseDate("2026-08-20", "en"), "August 20, 2026");
assert.equal(formattedReleaseDate("2026-08-20", "zh"), "2026年8月20日");
assert.equal(cacheIsFresh(1_000, 1_000 + 599_999), true);
assert.equal(cacheIsFresh(1_000, 1_000 + 600_000), false);

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
  const storage = createStorage({ feed, savedAt: 999_500 });
  let requestCount = 0;
  const controller = controllerFor({
    documentObject,
    fetchFunction: async () => { requestCount += 1; throw new Error("fresh cache must not fetch"); },
    storage,
  });
  assert.equal(await controller.load(), "fresh-cache");
  assert.equal(requestCount, 0);
  assert.equal(documentObject.list.children.length, feed.releases.length);
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
      assert.equal(url, "official-app-releases.json");
      assert.equal(options.cache, "no-cache");
      assert.equal(options.credentials, "omit");
      assert.equal(options.referrerPolicy, "no-referrer");
      return { ok: true, json: async () => clone(feed) };
    },
    storage,
  });
  assert.equal(await controller.load(), "network");
  assert.equal(requestCount, 1);
  assert.match(storage.values.get("rabbisir-official-app-releases-v1"), /Rabbisir 0\.1\.0/);
  assert.match(documentObject.list.textContent, /Maintenance update/);
  assert.equal(documentObject.list.getAttribute("aria-busy"), "false");
}

{
  const documentObject = createFakeDocument();
  let finishRequest;
  const controller = controllerFor({
    documentObject,
    fetchFunction: () => new Promise((resolve) => { finishRequest = resolve; }),
    storage: createStorage(),
  });
  const loading = controller.load();
  documentObject.documentElement.lang = "zh-CN";
  controller.rerender();
  assert.equal(documentObject.status.textContent, "Loading official release information…");
  assert.equal(documentObject.list.getAttribute("aria-busy"), "true");
  finishRequest({ ok: true, json: async () => clone(feed) });
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
  const storage = createStorage({ feed, savedAt: 1 });
  const controller = controllerFor({
    documentObject,
    fetchFunction: async () => ({ ok: false, status: 429 }),
    storage,
  });
  assert.equal(await controller.load(), "saved-fallback");
  assert.equal(documentObject.list.children.length, feed.releases.length);
  assert.equal(documentObject.status.textContent, "Showing saved release information while the live source is unavailable.");
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
    fetchFunction: async () => ({ ok: true, json: async () => clone(feed) }),
    storage: createStorage(),
  });
  await controller.load();
  documentObject.documentElement.lang = "zh-CN";
  controller.rerender();
  assert.match(documentObject.list.textContent, /维护更新/);
  assert.equal(documentObject.status.textContent, "正式版本信息已更新。");
}

console.log("test-official-release-feed: schema, receipt, network, timeout, cache, fallback, rendering, language, and accessibility tests passed");
