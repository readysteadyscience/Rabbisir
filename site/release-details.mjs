import {
  localizedReleaseText,
  mergeNormalizedReleaseFeeds,
  normalizeOfficialReleaseFeed,
} from "./release-data.mjs";

export const feedURL = "https://raw.githubusercontent.com/readysteadyscience/Rabbisir-Releases/main/official-app-releases.json";
export const fallbackFeedURL = "official-app-releases.json";
export const latestDownloadURL = "https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg";
const cacheKey = "rabbisir-official-app-releases-v2";
const cacheLifetimeMilliseconds = 5 * 60 * 1000;
const requestTimeoutMilliseconds = 8_000;

export function cacheIsFresh(savedAt, now = Date.now()) {
  return Number.isFinite(savedAt)
    && savedAt <= now
    && now - savedAt < cacheLifetimeMilliseconds;
}

export function formattedReleaseDate(publishedOn, language) {
  const locale = language === "zh" ? "zh-CN" : "en-US";
  return new Intl.DateTimeFormat(locale, {
    day: "numeric",
    month: "long",
    timeZone: "UTC",
    year: "numeric",
  }).format(new Date(`${publishedOn}T00:00:00Z`));
}

export function createReleaseDetailsController({
  documentObject,
  fetchFunction,
  storage,
  now = Date.now,
  timeoutMilliseconds = requestTimeoutMilliseconds,
  setTimeoutFunction = setTimeout,
  clearTimeoutFunction = clearTimeout,
}) {
  let displayedFeed = null;
  let displayedAsFallback = false;
  let displayState = "loading";

  function currentLanguage() {
    return documentObject.documentElement.lang.toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  function copy(en, zh) {
    return currentLanguage() === "zh" ? zh : en;
  }

  function readCachedFeed() {
    try {
      const cached = JSON.parse(storage.getItem(cacheKey));
      const primary = normalizeOfficialReleaseFeed(cached.feed);
      const history = cached.history ? normalizeOfficialReleaseFeed(cached.history) : null;
      return {
        feed: history ? mergeNormalizedReleaseFeeds(primary, history) : primary,
        history,
        historyRaw: cached.history ?? null,
        savedAt: cached.savedAt,
      };
    } catch {
      return null;
    }
  }

  function writeCachedFeed(feed, history) {
    try {
      storage.setItem(cacheKey, JSON.stringify({ feed, history, savedAt: now() }));
    } catch {
      // A non-persistent App browser can deny storage; the live response still renders.
    }
  }

  function element(name, className, text) {
    const node = documentObject.createElement(name);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function renderFeed(feed, fallback = false) {
    displayedFeed = feed;
    displayedAsFallback = fallback;
    displayState = fallback ? "fallback" : "feed";
    const language = currentLanguage();
    const list = documentObject.querySelector("#release-list");
    const fragment = documentObject.createDocumentFragment();

    feed.releases.forEach((release, index) => {
      const article = element("article", `release-entry${index === 0 ? " release-entry-current" : ""}`);
      const header = element("header", "release-entry-header");
      const headingGroup = element("div", "release-entry-heading");
      if (index === 0) {
        headingGroup.append(element("p", "release-latest-label", copy("Latest release", "最新版本")));
      }
      headingGroup.append(element("h3", "release-version", release.version));
      if (release.build) {
        headingGroup.append(element("p", "release-build", copy(`Build ${release.build}`, `构建 ${release.build}`)));
      }
      const time = element("time", "release-date", formattedReleaseDate(release.publishedOn, language));
      time.dateTime = release.publishedOn;
      header.append(headingGroup, time);

      const body = element("div", "release-entry-body");
      if (Array.isArray(release.releaseTypes) && release.releaseTypes.length > 0) {
        const types = element("ul", "release-types");
        types.setAttribute("aria-label", copy("Release types", "发布类型"));
        release.releaseTypes.forEach((type) => {
          types.append(element("li", "release-type", localizedReleaseText(type.label, language)));
        });
        body.append(types);
      }
      body.append(
        element("p", "release-entry-title", localizedReleaseText(release.title, language)),
        element("p", "release-entry-summary", localizedReleaseText(release.summary, language)),
      );
      const highlights = element("ul", "release-highlights");
      release.highlights.forEach((highlight) => {
        highlights.append(element("li", "", localizedReleaseText(highlight, language)));
      });
      body.append(highlights);
      const actions = element("div", "release-entry-actions");
      const download = element("a", "release-download-link", copy("Download DMG", "下载 DMG"));
      download.setAttribute("href", index === 0 ? latestDownloadURL : release.releaseURL);
      download.setAttribute("aria-label", index === 0
        ? copy(`Download ${release.version} DMG`, `下载 ${release.version} DMG`)
        : copy(`View ${release.version} release`, `查看 ${release.version} Release`));
      if (index !== 0) download.textContent = copy("View release", "查看 Release");
      actions.append(download);
      body.append(actions);
      article.append(header, body);
      fragment.append(article);
    });

    list.replaceChildren(fragment);
    list.setAttribute("aria-busy", "false");
    documentObject.querySelector("#release-feed-status").textContent = fallback
      ? copy("Showing verified fallback release information while the live source is unavailable.", "实时数据暂不可用，当前显示已验证的备用版本信息。")
      : copy("Official release information is up to date.", "正式版本信息已更新。");
  }

  function renderUnavailable() {
    displayedFeed = null;
    displayedAsFallback = false;
    displayState = "unavailable";
    const list = documentObject.querySelector("#release-list");
    const article = element("article", "release-empty");
    article.append(
      element("p", "release-empty-title", copy("Release information is temporarily unavailable.", "版本信息暂时不可用。")),
      element("p", "", copy("The page is still available. Please try again later.", "页面仍可正常使用，请稍后再试。")),
    );
    list.replaceChildren(article);
    list.setAttribute("aria-busy", "false");
    documentObject.querySelector("#release-feed-status").textContent = copy(
      "The official release source could not be reached.",
      "暂时无法连接正式版本数据源。",
    );
  }

  async function fetchFeed(url) {
    const controller = new AbortController();
    const timeout = setTimeoutFunction(() => controller.abort(), timeoutMilliseconds);
    try {
      const response = await fetchFunction(url, {
        cache: "no-cache",
        credentials: "omit",
        headers: { Accept: "application/json" },
        referrerPolicy: "no-referrer",
        signal: controller.signal,
      });
      if (!response.ok) throw new Error("official release source is unavailable");
      const rawFeed = await response.json();
      return { normalized: normalizeOfficialReleaseFeed(rawFeed), raw: rawFeed };
    } finally {
      clearTimeoutFunction(timeout);
    }
  }

  async function load() {
    const cached = readCachedFeed();
    if (cached) renderFeed(cached.feed);
    if (cached?.history && cacheIsFresh(cached.savedAt, now())) return "fresh-cache";

    const [liveResult, bundledResult] = await Promise.allSettled([
      fetchFeed(feedURL),
      fetchFeed(fallbackFeedURL),
    ]);
    if (liveResult.status === "fulfilled") {
      const history = bundledResult.status === "fulfilled"
        ? bundledResult.value
        : cached?.history
          ? { normalized: cached.history, raw: cached.historyRaw }
          : null;
      writeCachedFeed(liveResult.value.raw, history?.raw ?? null);
      renderFeed(history
        ? mergeNormalizedReleaseFeeds(liveResult.value.normalized, history.normalized)
        : liveResult.value.normalized);
      return "network";
    }
    if (cached) {
      renderFeed(cached.feed, true);
      return "saved-fallback";
    }
    if (bundledResult.status === "fulfilled") {
      renderFeed(bundledResult.value.normalized, true);
      return "bundled-fallback";
    }
    renderUnavailable();
    return "unavailable";
  }

  function rerender() {
    if (displayedFeed) renderFeed(displayedFeed, displayedAsFallback);
    else if (displayState === "unavailable") renderUnavailable();
  }

  return { load, rerender };
}

if (typeof document !== "undefined") {
  const controller = createReleaseDetailsController({
    documentObject: document,
    fetchFunction: fetch,
    storage: localStorage,
  });
  document.querySelector(".language-switch")?.addEventListener("click", controller.rerender);
  new MutationObserver(controller.rerender).observe(document.documentElement, {
    attributeFilter: ["lang"],
    attributes: true,
  });
  controller.load();
}
