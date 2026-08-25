const localizedKeys = ["en", "zh"];
const releaseKeys = ["highlights", "publishedOn", "summary", "title", "version"];
const topLevelKeys = ["contentReceiptSHA256", "latest", "releases", "schemaVersion", "source", "updatedAt"];
const sourceKeys = ["channel", "receipt"];

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

export function validateOfficialReleaseFeed(value) {
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

export function localizedReleaseText(value, language) {
  return value[language === "zh" ? "zh" : "en"];
}
