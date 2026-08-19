# Runtime provenance

Rabbisir's generated compatibility runtime is reproducible from the official DeepSeek Harness
revision and the tracked inputs in this directory. Generated Node and runtime payloads remain ignored
by Git; this directory records only auditable source transformations and expected output metadata.

[`contract.json`](contract.json) pins:

- the official repository, commit, Git tree, and reported runtime version;
- the ordered compatibility patches and their SHA-256 digests;
- the Node distribution, Node binary, package-manager version, official package archive URL and
  SHA-256, and lockfile digests;
- the exact manifest schema and Rabbisir product version projected into the carrier;
- the deterministic assembly rules, canonical launch closure, and canonical output inventory.

The first patch is Rabbisir's compatibility change set. The second removes an absolute-checkout-path
input from CSS module hashing. The rebuild also runs client bundle configurations sequentially,
adds the required non-optional workspace peer-dependency closure from the same built source snapshot,
normalizes generated CSS export key order, and replaces generated absolute source roots with the
fixed `rabbisir-upstream-source` token. Peer supplements are restricted to package-declared `lib`
runtime outputs, and their expected count is pinned in the contract. These transformations preserve
runtime semantics while making the output independent of checkout location and scheduling order.

To rebuild, provide a separate checkout that has the official remote and pinned commit, plus the
official Node distribution named in the contract:

```sh
scripts/rebuild-vendor-runtime.sh \
  <official-upstream-checkout> \
  <node-distribution-root> \
  <verified-pnpm-archive> \
  <new-output-root>
```

The output path must not exist. The script downloads neither upstream source nor the package
manager. The caller must supply the pnpm archive named by the contract; its official npm registry
URL and SHA-256 are verified before extraction, and a missing or changed archive fails closed. This
replaces online `corepack prepare` and makes the package-manager executable an explicit local input.
Dependency installation remains governed by the pinned upstream lockfile and registry integrity
metadata; a rebuild is not described as fully network-offline unless its isolated pnpm store has
already been populated from separately verified artifacts. The script refuses an unrecognized
remote, verifies every pinned input, builds in a disposable directory, and writes a deterministic
`.rabbisir-runtime-provenance.json` receipt at the carrier root only after the canonical inventory
matches the contract. The inventory and receipt cover the launcher, Node, Node's spawn helper, and
the generated runtime tree as one launch closure. The manifest is deliberately outside that payload
inventory to avoid a contract-digest self-reference; instead it is an exact, eight-field projection
derived from the same trusted contract. Unknown, missing, or changed manifest fields fail closed, and
the receipt separately binds the contract digest. `scripts/stage-vendor-runtime.sh` accepts only a
schema-3 receipted carrier whose strict manifest, canonical executable paths, receipt, inventory,
required workspace dependency closure, native projection, Node binary, spawn helper, and reported
version all verify.

The inventory hashes relative path, normalized executable mode, file content, and safe in-root
symbolic-link target. Timestamps, ownership, the receipt itself, and the absolute build directory are
excluded. Broken or escaping symbolic links fail closed.
