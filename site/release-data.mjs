const localizedKeys = ["en", "zh"];
const releaseKeys = ["highlights", "publishedOn", "summary", "title", "version"];
const topLevelKeys = ["contentReceiptSHA256", "latest", "releases", "schemaVersion", "source", "updatedAt"];
const sourceKeys = ["channel", "receipt"];
const authorityFeedKeys = ["$schema", "authority", "channel", "latest", "releases", "schemaVersion", "updatedAt"];
const authorityKeys = ["appcastURL", "repository", "stableDownloadURL"];
const authorityLatestKeys = ["build", "tag", "version"];
const authorityReleaseKeys = ["assets", "build", "categories", "publishedOn", "releaseURL", "selectedTypes", "tag", "version"];
const authorityAssetKeys = ["name", "sha256", "size", "url"];
const releaseTypeOrder = ["feature", "optimization", "fix"];
const releaseTypeLabels = {
  feature: { en: "Feature update", zh: "功能更新" },
  optimization: { en: "Capability improvements", zh: "能力优化" },
  fix: { en: "Bug fixes", zh: "Bug 修复" },
};
const authorityRepository = "readysteadyscience/Rabbisir-Releases";
const authorityAppcastURL = "https://raw.githubusercontent.com/readysteadyscience/Rabbisir-Releases/main/appcast.xml";
const authorityStableDownloadURL = "https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg";

function hasExactKeys(value, keys) {
  return value !== null
    && typeof value === "object"
    && !Array.isArray(value)
    && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());
}

function requireLocalized(value, label, maximumLength) {
  if (!hasExactKeys(value, localizedKeys)) {
    throw new Error(`${label} must contain only en and zh`);
  }
  for (const language of localizedKeys) {
    const text = value[language];
    if (typeof text !== "string" || text.trim() !== text || text.length < 1 || text.length > maximumLength) {
      throw new Error(`${label}.${language} is invalid`);
    }
    if (/[<>]/.test(text)) {
      throw new Error(`${label}.${language} contains unsupported content`);
    }
  }
}

function versionParts(version) {
  const number = "(0|[1-9]\\d*)";
  const match = new RegExp(`^Rabbisir ${number}\\.${number}\\.${number}(?: · r${number}\\.(\\d{2}))?$`).exec(version);
  if (!match) return null;
  return {
    legacyRevision: match[4] === undefined ? null : [BigInt(match[4]), BigInt(match[5])],
    semanticVersion: match.slice(1, 4).map(BigInt),
  };
}

function canonicalVersionParts(version) {
  const number = "(0|[1-9]\\d*)";
  const match = new RegExp(`^${number}\\.${number}\\.${number}$`).exec(version);
  return match ? match.slice(1, 4).map(BigInt) : null;
}

function compareVersionDescending(left, right) {
  const leftParts = versionParts(left);
  const rightParts = versionParts(right);
  if (!leftParts || !rightParts) return 0;
  for (let index = 0; index < leftParts.semanticVersion.length; index += 1) {
    if (rightParts.semanticVersion[index] > leftParts.semanticVersion[index]) return 1;
    if (rightParts.semanticVersion[index] < leftParts.semanticVersion[index]) return -1;
  }
  const leftRevision = leftParts.legacyRevision ?? [-1n, -1n];
  const rightRevision = rightParts.legacyRevision ?? [-1n, -1n];
  for (let index = 0; index < leftRevision.length; index += 1) {
    if (rightRevision[index] > leftRevision[index]) return 1;
    if (rightRevision[index] < leftRevision[index]) return -1;
  }
  return 0;
}

function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().startsWith(value);
}

function compareCanonicalVersionDescending(left, right) {
  const leftParts = canonicalVersionParts(left);
  const rightParts = canonicalVersionParts(right);
  if (!leftParts || !rightParts) return 0;
  for (let index = 0; index < leftParts.length; index += 1) {
    if (rightParts[index] > leftParts[index]) return 1;
    if (rightParts[index] < leftParts[index]) return -1;
  }
  return 0;
}

function validBuild(value) {
  return typeof value === "string" && /^[1-9]\d*$/.test(value);
}

function validateAuthorityReleaseFeed(value) {
  if (!hasExactKeys(value, authorityFeedKeys)
    || value.$schema !== "./official-app-releases.schema.json"
    || value.schemaVersion !== 2
    || value.channel !== "production"
    || typeof value.updatedAt !== "string"
    || Number.isNaN(Date.parse(value.updatedAt))) {
    throw new Error("unsupported official release authority schema");
  }
  if (!hasExactKeys(value.authority, authorityKeys)
    || value.authority.repository !== authorityRepository
    || value.authority.appcastURL !== authorityAppcastURL
    || value.authority.stableDownloadURL !== authorityStableDownloadURL) {
    throw new Error("official release authority differs from the reviewed channel");
  }
  if (!hasExactKeys(value.latest, authorityLatestKeys)
    || !canonicalVersionParts(value.latest.version)
    || !validBuild(value.latest.build)
    || value.latest.tag !== `v${value.latest.version}`) {
    throw new Error("official release latest identity is invalid");
  }
  if (!Array.isArray(value.releases) || value.releases.length < 1 || value.releases.length > 50) {
    throw new Error("official release authority history is invalid");
  }

  const versions = new Set();
  const builds = new Set();
  let previousDate = null;
  let previousVersion = null;
  value.releases.forEach((release, releaseIndex) => {
    if (!hasExactKeys(release, authorityReleaseKeys)
      || !canonicalVersionParts(release.version)
      || !validBuild(release.build)
      || release.tag !== `v${release.version}`
      || !validDate(release.publishedOn)
      || release.releaseURL !== `https://github.com/${authorityRepository}/releases/tag/${release.tag}`) {
      throw new Error(`official release ${releaseIndex} identity is invalid`);
    }
    if (versions.has(release.version) || builds.has(release.build)) {
      throw new Error("official release versions and builds must be unique");
    }
    versions.add(release.version);
    builds.add(release.build);
    if (!Array.isArray(release.selectedTypes)
      || release.selectedTypes.length < 1
      || new Set(release.selectedTypes).size !== release.selectedTypes.length
      || release.selectedTypes.some((type) => !releaseTypeOrder.includes(type))) {
      throw new Error(`official release ${releaseIndex} selected types are invalid`);
    }
    const orderedTypes = releaseTypeOrder.filter((type) => release.selectedTypes.includes(type));
    if (JSON.stringify(release.selectedTypes) !== JSON.stringify(orderedTypes)
      || !hasExactKeys(release.categories, orderedTypes)) {
      throw new Error(`official release ${releaseIndex} categories differ from selected types`);
    }
    orderedTypes.forEach((type) => {
      const items = release.categories[type];
      if (!Array.isArray(items) || items.length < 1 || items.length > 8) {
        throw new Error(`official release ${releaseIndex} ${type} items are invalid`);
      }
      items.forEach((item, itemIndex) => requireLocalized(
        item,
        `official release ${releaseIndex} ${type} item ${itemIndex}`,
        180,
      ));
    });
    if (!Array.isArray(release.assets) || release.assets.length < 3 || release.assets.length > 8) {
      throw new Error(`official release ${releaseIndex} asset closure is invalid`);
    }
    const assetNames = new Set();
    release.assets.forEach((asset, assetIndex) => {
      if (!hasExactKeys(asset, authorityAssetKeys)
        || typeof asset.name !== "string"
        || !/^[A-Za-z0-9._-]+$/.test(asset.name)
        || assetNames.has(asset.name)
        || !Number.isSafeInteger(asset.size)
        || asset.size < 1
        || !/^[0-9a-f]{64}$/.test(asset.sha256)
        || asset.url !== `https://github.com/${authorityRepository}/releases/download/${release.tag}/${asset.name}`) {
        throw new Error(`official release ${releaseIndex} asset ${assetIndex} is invalid`);
      }
      assetNames.add(asset.name);
    });
    if (!assetNames.has("Rabbisir.dmg")) {
      throw new Error(`official release ${releaseIndex} lacks its stable DMG alias`);
    }
    if (previousDate && release.publishedOn > previousDate) {
      throw new Error("official release authority must be newest first");
    }
    if (previousDate === release.publishedOn
      && compareCanonicalVersionDescending(previousVersion, release.version) > 0) {
      throw new Error("same-day official release authority must be newest first");
    }
    previousDate = release.publishedOn;
    previousVersion = release.version;
  });
  const first = value.releases[0];
  if (first.version !== value.latest.version
    || first.build !== value.latest.build
    || first.tag !== value.latest.tag) {
    throw new Error("official release latest identity must match the first release");
  }
  return value;
}

export function validateOfficialReleaseFeed(value) {
  if (value?.schemaVersion === 2) return validateAuthorityReleaseFeed(value);
  if (!hasExactKeys(value, topLevelKeys) || value.schemaVersion !== 1) {
    throw new Error("unsupported official release feed schema");
  }
  if (typeof value.updatedAt !== "string" || Number.isNaN(Date.parse(value.updatedAt))) {
    throw new Error("official release feed updatedAt is invalid");
  }
  if (!/^[0-9a-f]{64}$/.test(value.contentReceiptSHA256)) {
    throw new Error("official release feed content receipt is invalid");
  }
  if (!hasExactKeys(value.source, sourceKeys)
    || value.source.channel !== "rabbisir-official-app"
    || value.source.receipt !== "official-app-release-source.json") {
    throw new Error("official release feed source receipt is invalid");
  }
  if (!Array.isArray(value.releases) || value.releases.length < 1 || value.releases.length > 50) {
    throw new Error("official release feed release count is invalid");
  }

  const versions = new Set();
  let previousDate = null;
  let previousVersion = null;
  for (const [index, release] of value.releases.entries()) {
    if (!hasExactKeys(release, releaseKeys) || !versionParts(release.version)) {
      throw new Error(`release ${index} shape or version is invalid`);
    }
    if (versions.has(release.version)) throw new Error("official release versions must be unique");
    versions.add(release.version);
    if (!validDate(release.publishedOn)) throw new Error(`release ${index} date is invalid`);
    requireLocalized(release.title, `release ${index} title`, 80);
    requireLocalized(release.summary, `release ${index} summary`, 280);
    if (!Array.isArray(release.highlights) || release.highlights.length < 1 || release.highlights.length > 8) {
      throw new Error(`release ${index} highlights are invalid`);
    }
    release.highlights.forEach((highlight, highlightIndex) => {
      requireLocalized(highlight, `release ${index} highlight ${highlightIndex}`, 180);
    });
    if (previousDate && release.publishedOn > previousDate) {
      throw new Error("official releases must be newest first");
    }
    if (previousDate === release.publishedOn && compareVersionDescending(previousVersion, release.version) > 0) {
      throw new Error("same-day official releases must be newest first");
    }
    previousDate = release.publishedOn;
    previousVersion = release.version;
  }
  const latestParts = typeof value.latest === "string" ? versionParts(value.latest) : null;
  if (!latestParts || latestParts.legacyRevision !== null || value.latest !== value.releases[0].version) {
    throw new Error("latest must identify the first official release");
  }
  return value;
}

function legacyReleaseURL(version) {
  const match = /^Rabbisir (\d+\.\d+\.\d+)(?: · r(\d+\.\d{2}))?$/.exec(version);
  if (!match) return "https://github.com/readysteadyscience/Rabbisir/releases";
  const tag = match[2] ? `v${match[1]}-r${match[2]}` : `v${match[1]}`;
  return `https://github.com/readysteadyscience/Rabbisir/releases/tag/${tag}`;
}

function authoritySummary(selectedTypes) {
  const labels = selectedTypes.map((type) => releaseTypeLabels[type]);
  return {
    en: `This release includes ${labels.map((label) => label.en.toLowerCase()).join(", ")}.`,
    zh: `本次版本包含：${labels.map((label) => label.zh).join("、")}。`,
  };
}

export function normalizeOfficialReleaseFeed(value) {
  const feed = validateOfficialReleaseFeed(value);
  if (feed.schemaVersion === 1) {
    return {
      latest: feed.latest,
      releases: feed.releases.map((release) => ({
        ...release,
        build: null,
        releaseTypes: [],
        releaseURL: legacyReleaseURL(release.version),
      })),
      schemaVersion: 1,
      updatedAt: feed.updatedAt,
    };
  }
  return {
    latest: `Rabbisir ${feed.latest.version}`,
    releases: feed.releases.map((release) => {
      const releaseTypes = release.selectedTypes.map((type) => ({
        key: type,
        label: releaseTypeLabels[type],
      }));
      return {
        build: release.build,
        highlights: release.selectedTypes.flatMap((type) => release.categories[type]),
        publishedOn: release.publishedOn,
        releaseTypes,
        releaseURL: release.releaseURL,
        summary: authoritySummary(release.selectedTypes),
        title: {
          en: releaseTypes.map((type) => type.label.en).join(" · "),
          zh: releaseTypes.map((type) => type.label.zh).join(" · "),
        },
        version: `Rabbisir ${release.version}`,
      };
    }),
    schemaVersion: 2,
    updatedAt: feed.updatedAt,
  };
}

function normalizedVersionParts(version) {
  const match = /^Rabbisir (0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?: · r(0|[1-9]\d*)\.(\d{2}))?$/.exec(version);
  return match ? match.slice(1).map((part) => part === undefined ? -1n : BigInt(part)) : null;
}

function compareNormalizedReleases(left, right) {
  const dateOrder = right.publishedOn.localeCompare(left.publishedOn);
  if (dateOrder !== 0) return dateOrder;
  const leftParts = normalizedVersionParts(left.version);
  const rightParts = normalizedVersionParts(right.version);
  if (!leftParts || !rightParts) return left.version.localeCompare(right.version);
  for (let index = 0; index < leftParts.length; index += 1) {
    if (rightParts[index] > leftParts[index]) return 1;
    if (rightParts[index] < leftParts[index]) return -1;
  }
  return 0;
}

export function mergeNormalizedReleaseFeeds(primary, supplemental) {
  const seenVersions = new Set();
  const releases = [...primary.releases, ...supplemental.releases]
    .filter((release) => {
      if (seenVersions.has(release.version)) return false;
      seenVersions.add(release.version);
      return true;
    })
    .sort(compareNormalizedReleases);
  return { ...primary, releases };
}

export function localizedReleaseText(value, language) {
  return value[language === "zh" ? "zh" : "en"];
}
