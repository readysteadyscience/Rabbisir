#!/usr/bin/env node

import fs from "node:fs";

function fail() {
  process.stderr.write("verify-public-dependency-lock: public Swift dependency lock is invalid\n");
  process.exit(1);
}

const resolved = JSON.parse(fs.readFileSync(new URL("../Package.resolved", import.meta.url), "utf8"));
const expected = [
  {
    identity: "swift-syntax",
    location: "https://github.com/swiftlang/swift-syntax.git",
    revision: "4799286537280063c85a32f09884cfbca301b1a1",
    version: "602.0.0",
  },
  {
    branch: "swift-6.2.3-RELEASE",
    identity: "swift-testing",
    location: "https://github.com/swiftlang/swift-testing",
    revision: "48a471ab313e858258ab0b9b0bf2cea55a50cefb",
  },
];

if (resolved.version !== 3 || !Array.isArray(resolved.pins) || resolved.pins.length !== expected.length) {
  fail();
}
const actual = resolved.pins
  .map((pin) => ({
    branch: pin.state.branch,
    identity: pin.identity,
    location: pin.location,
    revision: pin.state.revision,
    version: pin.state.version,
  }))
  .sort((left, right) => left.identity.localeCompare(right.identity));
for (let index = 0; index < expected.length; index += 1) {
  const expectedKeys = Object.keys(expected[index]).sort();
  const actualEntry = Object.fromEntries(
    Object.entries(actual[index]).filter(([, value]) => value !== undefined)
  );
  if (
    JSON.stringify(Object.keys(actualEntry).sort()) !== JSON.stringify(expectedKeys) ||
    expectedKeys.some((key) => actualEntry[key] !== expected[index][key])
  ) {
    fail();
  }
}

const manifest = fs.readFileSync(new URL("../Package.swift", import.meta.url), "utf8");
const dependencyDeclarations = manifest.match(/\.package\(/g) ?? [];
if (
  dependencyDeclarations.length !== 1 ||
  !manifest.includes('url: "https://github.com/swiftlang/swift-testing"') ||
  !manifest.includes('revision: "swift-6.2.3-RELEASE"')
) {
  fail();
}

const workflow = fs.readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8");
if (!workflow.includes("actions/checkout@11d5960a326750d5838078e36cf38b85af677262")) {
  fail();
}

process.stdout.write("verify-public-dependency-lock: Swift test dependencies match the reviewed revisions\n");
