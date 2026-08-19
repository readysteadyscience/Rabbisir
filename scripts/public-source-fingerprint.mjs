#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [rootArgument] = process.argv.slice(2);
if (!rootArgument || process.argv.length !== 3) {
  process.stderr.write("usage: public-source-fingerprint.mjs <public-source-root>\n");
  process.exit(64);
}

const root = fs.realpathSync(rootArgument);
const files = [];

function visit(directory, prefix = "") {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    const absolute = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      throw new Error("public source fingerprints reject symbolic links");
    }
    if (entry.isDirectory()) {
      visit(absolute, relative);
    } else if (entry.isFile()) {
      files.push({ absolute, relative });
    } else {
      throw new Error("public source fingerprints accept only files and directories");
    }
  }
}

try {
  visit(root);
  files.sort((left, right) =>
    Buffer.compare(Buffer.from(left.relative, "utf8"), Buffer.from(right.relative, "utf8"))
  );
  const digest = crypto.createHash("sha256");
  digest.update("rabbisir-public-source-v1\0");
  for (const file of files) {
    const stat = fs.statSync(file.absolute);
    const mode = stat.mode & 0o111 ? "755" : "644";
    const content = fs.readFileSync(file.absolute);
    digest.update(`${file.relative.length}:${file.relative}\0${mode}\0${content.length}:`);
    digest.update(content);
    digest.update("\0");
  }
  process.stdout.write(`${digest.digest("hex")}\n`);
} catch {
  process.stderr.write("public-source-fingerprint: public source tree is invalid\n");
  process.exit(1);
}
