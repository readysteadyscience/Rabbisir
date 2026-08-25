# Public website

The public GitHub Pages packaging root is [`site/`](../site). The site uses a fixed-dark responsive
layout, bilingual content, a language switch, a contact dialog, and reduced-motion behavior.

## Public asset boundary

The website:

- links to the official DeepSeek Harness repository using bilingual plain text and states that
  Rabbisir is independent and not affiliated with, sponsored by, or endorsed by DeepSeek;
- uses the unchanged X Brand Toolkit symbol only to identify the adjacent YelZap profile link;
- uses a clear `WeChat` / `微信` text button for the creator-contact QR because no redistributable
  WeChat logo is included;
- uses the unchanged official Blurple Discord symbol for the community link; and
- uses the creator-authorized Rabbisir mark and avatar only as product and creator identity.

Every packaged website asset and its digest is listed in
[`Legal/SITE_ASSET_MANIFEST.sha256`](../Legal/SITE_ASSET_MANIFEST.sha256), with ownership and usage
boundaries in [`Legal/BRAND_ASSETS.md`](../Legal/BRAND_ASSETS.md). DeepSeek graphics and unverified
WeChat graphics are excluded. Third-party marks and creator identity/contact assets are not licensed
under Rabbisir's MIT source license.

The shared site script stores only the language choice under `rabbisir-language`; it contains no
analytics, cookies, credentials, updater logic, payment path, or automatic external navigation. The
separate Release Details module performs only the documented same-origin official-release-feed
request and uses a dedicated ten-minute local cache.

Run the local and CI-equivalent gates after website-source changes:

```sh
scripts/verify-pages-site.sh
scripts/verify-public-repository.sh
```

## Official App release information channel

The stable Release Details URL is [`site/download.html`](../site/download.html). Despite the retained
path, it is a version-history page rather than an installer page. It loads only the same-origin,
public-read-only [`site/official-app-releases.json`](../site/official-app-releases.json) document and
never reads a GitHub repository's Releases API, an Appcast, a private repository, or a credential.
Open-source Releases, distribution assets and automatic-update metadata do not define this feed.

Schema version 1 is a complete replacement document with a latest-version pointer, newest-first
bilingual history, ISO publication dates, plain-text summaries and highlights, and a content
receipt. It points to `official-app-release-source.json`; the companion receipt repeats the channel,
latest version, update time and content receipt, and both JSON files have SHA-256 sidecars. This
four-file closure avoids circular hashes and is listed in `PagesSourceManifest.json` for atomic Pages
publication. `scripts/verify-official-release-feed.mjs` checks schema, ordering, bilingual closure,
public-safe wording, feed/receipt agreement and both sidecars. Release text is rendered only through
DOM `textContent`.

An authorized formal App publication prepares and validates all four files in a temporary staging
root, binds them into the Pages source manifest and then publishes the Pages artifact. App publication
and website-data publication are separate results and must be read back independently. Rollback
republishes the previous accepted feed, source receipt and both sidecars without changing page code.
The browser keeps a validated feed for ten minutes; after expiry it revalidates once and continues to
show a valid saved feed when the data request fails.

Pages manifest schema 4 records two independent provenance bindings. `productArtifactSource` remains
the commit and tree that produced the signed and notarized App artifacts; `websiteToolingSource`
records the clean commit and tree used to generate the Pages capsule plus its exact overlay-receipt
digest. A website-tooling repair never relabels frozen App bytes as a new product build, and a frozen
product manifest cannot be used with unreceipted or dirty website tooling.
Release-time website generation starts from the exact reviewed public Git tree and preserves that
tree's independent `AppVersion.swift` and runtime provenance byte for byte. It never accepts or copies
the official App's VendorRuntime, AppVersion or private product-source files into the public Pages
source. Product provenance remains a receipt binding only; website data, Appcast and the stable-DMG
deployment record are the release-time projection.
When a website-only tool repair follows already notarized artifacts,
`prepare-frozen-pages-continuation.sh` is the only supported local continuation entrypoint. It
revalidates the frozen preflight and artifact manifests plus their sidecars and exact ZIP, DMG and
Appcast bytes, then produces a new delivery plan, Pages source and
`WebsiteDeliveryContinuationReceipt.json` without signing, notarization, GitHub writes or Pages
deployment. The migrated product-artifact envelope keeps its canonical payload digest internally;
its `.sha256` sidecar covers the exact serialized file, and the continuation receipt records both.

## Direct download continuity

The homepage primary action uses the permanent Pages URL
`https://readysteadyscience.github.io/Rabbisir/Rabbisir.dmg`. The authorized release transaction
records the reviewed versioned Release DMG URL, size and SHA-256 in the Pages source manifest. The
DMG never enters Git history: after the Release asset has passed public readback, the explicit Pages
workflow downloads it anonymously, verifies the frozen record, and materializes the same-origin
stable filename only inside the temporary deployment artifact.
Versioned filenames, sizes, SHA-256 values, the canonical Release link and installation-acceptance
status remain in [`site/DOWNLOADS.md`](../site/DOWNLOADS.md). `Rabbisir Open` contributor builds are
not official downloadable Apps. Appcast, Release assets and update behavior remain unchanged.

## 中文边界

公开 GitHub Pages 打包根及页面入口均位于 [`site/`](../site)。网站保留黑底响应式布局、双语切换、
联系弹窗和减少动态效果支持。DeepSeek 仅使用醒目的双语文字链接及独立性声明；X、Discord、
Rabbisir 标识、创作者头像和微信联系二维码均遵守上文列出的公开资产用途与许可边界。

共享脚本只保存 `rabbisir-language` 语言选择，不包含分析、Cookie、凭据、更新、支付或自动外跳。
`site/download.html` 是稳定的正式版本详情地址，只读取同源的
`site/official-app-releases.json` 官网专用数据，不读取开源仓库 Release、Appcast、私有仓库或
任何凭据。正式 App 发布事务以完整替换方式生成并校验 feed、来源回执与各自摘要侧车，将四个
文件纳入 Pages 清单原子发布，并分别回读 App 发布与官网数据发布结果；官网更新失败不得伪装
为 App 发布成功。页面使用十分钟本地缓存，网络失败时优先显示已校验的旧数据，不会白屏。
Pages 清单 schema 4 分别记录 `productArtifactSource` 与 `websiteToolingSource`：前者始终绑定实际
生成已签名、公证 App 资产的 commit/tree，后者绑定生成官网胶囊的干净工具 commit/tree 与
overlay receipt 摘要。官网工具修复不得把冻结 App 字节重称为新产品构建，未签收或脏的官网工具
也不得与既有产品清单拼接发布。
正式发布时的官网生成只从精确审查过的公开 Git tree 起步，并逐字节保留该 tree 独立的
`AppVersion.swift` 与 runtime provenance；不得接收或复制正式 App 的 VendorRuntime、AppVersion
或私有产品源码到公开 Pages source。产品 provenance 只保留在回执绑定中，发布时仅投影官网数据、
Appcast 与稳定 DMG 部署记录。
若官网工具修复发生在 App 资产已公证之后，只能使用
`prepare-frozen-pages-continuation.sh` 做本地续接：重新校验冻结 preflight、ArtifactManifest、
两份 sidecar 以及精确 ZIP、DMG、Appcast 字节，再生成新的 plan、PagesSource 与
`WebsiteDeliveryContinuationReceipt.json`；该入口不签名、不公证、不写 GitHub，也不部署 Pages。
迁移后的产品产物 envelope 在内部保留规范 payload 摘要，`.sha256` sidecar 覆盖精确序列化文件，
续接回执同时记录两者。

首页主要下载操作固定使用
`https://readysteadyscience.github.io/Rabbisir/Rabbisir.dmg`。获授权的发布事务会把已审查的
版本化 Release DMG 的公开 URL、大小与 SHA-256 绑定到 Pages 来源清单；DMG 不进入 Git 历史。
Release 资产完成公开回读后，显式 Pages 工作流匿名下载并校验冻结记录，只在临时部署 artifact
中生成这个同源稳定文件名。
版本化文件名、大小、SHA-256、正式 Release 链接和安装验收状态继续保留在
[`site/DOWNLOADS.md`](../site/DOWNLOADS.md)；Appcast、Release 资产与自动更新行为均不改变。
本地 `Rabbisir Open` 构建不是官方安装包。
