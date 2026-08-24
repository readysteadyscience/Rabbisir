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

## Direct download continuity

The homepage primary action continues to use the permanent GitHub path
`releases/latest/download/Rabbisir.dmg`, so this page change does not alter the installer target.
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

首页主要下载操作继续固定使用 `releases/latest/download/Rabbisir.dmg`，因此版本页改造不改变
安装包目标。版本化文件名、大小、SHA-256、正式 Release 链接和安装验收状态继续保留在
[`site/DOWNLOADS.md`](../site/DOWNLOADS.md)；Appcast、Release 资产与自动更新行为均不改变。
本地 `Rabbisir Open` 构建不是官方安装包。
