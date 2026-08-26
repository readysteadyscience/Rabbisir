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
separate Release Details module reads the public release authority described below and uses a
dedicated five-minute local cache with the last bundled website snapshot as its final fallback.

Run the local and CI-equivalent gates after website-source changes:

```sh
scripts/verify-pages-site.sh
scripts/verify-public-repository.sh
```

## Official App release information channel

The stable Release Details URL is [`site/download.html`](../site/download.html). Despite the retained
path, it is a version-history page rather than an installer page. Its authority is the anonymous,
public-read-only
[`Rabbisir-Releases/official-app-releases.json`](https://raw.githubusercontent.com/readysteadyscience/Rabbisir-Releases/main/official-app-releases.json)
document. It never reads a private repository or a credential. The same-origin
[`site/official-app-releases.json`](../site/official-app-releases.json) file remains only as the last
bundled v0.1.4 fallback when neither a valid live response nor a valid browser cache is available,
and supplements historical versions that the live authority has not migrated yet. Live schema-2
records always win when the same display version exists in both sources.
Open-source Releases do not define this feed.

Authority schema version 2 carries the latest version/build/tag, a newest-first history, ISO
publication dates, every selected release type, bilingual category items, the canonical Release URL
and the public asset closure. The only accepted authority is
`readysteadyscience/Rabbisir-Releases`, with its fixed raw Appcast and stable DMG URLs. The website
validates this complete structure before rendering and displays all selected feature, optimization
and fix categories. Release text is rendered only through DOM `textContent`. The bundled schema-1
snapshot retains its existing content receipt and sidecars and is validated separately as fallback.

An authorized formal App publication updates and validates the authority document in the release
repository, independently of this static Pages deployment. The website code does not change for a
new version. The browser keeps a validated authority response for five minutes; after expiry it
revalidates once, keeps a valid saved response visible when the network fails, and finally uses the
bundled v0.1.4 snapshot rather than showing a blank page. Rolling back the website migration means
redeploying the previous Pages commit; rolling back release data means restoring the previous
validated release-repository commit. These remain separate actions and results.

The schema-4 `PagesSourceManifest.json` remains the immutable v0.1.4 legacy DMG/Appcast deployment
snapshot. Its product and website-tooling provenance describe that snapshot, not this later static
page-code migration; the current website source is identified by its public Git commit and Pages run.

The v0.1.4 `site/appcast.xml` is retained byte-for-byte as the legacy update channel. It may be
replaced once, only after the release owner provides a signed bridge whose enclosure identifies the
next official release in `Rabbisir-Releases`. Until that receipt exists, the old feed remains intact;
the website never manufactures an enclosure or signature. After the bridge, the release repository's
raw `appcast.xml` is the sole authority for newer installations.

## Direct download continuity

The homepage primary action permanently uses
`https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg`.
The release repository publishes that alias byte-identical to the current versioned DMG, so later
official releases update the download without changing or redeploying this website. The previous
Pages-hosted `Rabbisir.dmg` remains an unlinked migration rollback surface and is not the current
download authority.
The v0.1.4 migration snapshot remains in [`site/DOWNLOADS.md`](../site/DOWNLOADS.md) as historical
evidence; current versioned assets and checksums live in the release repository. `Rabbisir Open`
contributor builds are not official downloadable Apps.

## 中文边界

公开 GitHub Pages 打包根及页面入口均位于 [`site/`](../site)。网站保留黑底响应式布局、双语切换、
联系弹窗和减少动态效果支持。DeepSeek 仅使用醒目的双语文字链接及独立性声明；X、Discord、
Rabbisir 标识、创作者头像和微信联系二维码均遵守上文列出的公开资产用途与许可边界。

共享脚本只保存 `rabbisir-language` 语言选择，不包含分析、Cookie、凭据、更新、支付或自动外跳。
`site/download.html` 是稳定的正式版本详情地址，权威数据源为公开只读的
`https://raw.githubusercontent.com/readysteadyscience/Rabbisir-Releases/main/official-app-releases.json`；
不读取私有仓库或任何凭据。schema 2 包含最新版本/build/tag、全部已选发布类型、各类型双语说明、
Release URL 与资产闭包。页面严格校验后展示；五分钟缓存失效后重新请求，失败时先保留已验证缓存，
最后回退到站内 v0.1.4 schema-1 快照，不会白屏。站内快照还会补齐权威数据尚未迁入的历史版本；
同一显示版本冲突时始终以线上 schema 2 为准。以后正式版本只更新发行仓库数据，不再重新部署整站。
schema-4 `PagesSourceManifest.json` 只描述 v0.1.4 旧 DMG/Appcast 部署快照；本次页面源码以公开
Git commit 与 Pages run 为准，不把旧工具 provenance 重称为本次迁移来源。

旧 `site/appcast.xml` 保持 v0.1.4 已签名原字节。只有发行负责人提供指向下一正式版本且签名、
enclosure 均已回读的桥接回执后，官网才能对它做一次替换；当前不得猜测或生成更新条目。桥接完成后，
新安装版只使用发行仓库 raw `appcast.xml` 权威 feed。

首页主要下载操作永久固定使用
`https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg`。
发行仓库保证该别名与当前版本化 DMG 同字节，因此后续版本无需修改或重新部署官网。旧 Pages
`Rabbisir.dmg` 仅作为未链接的迁移回滚面，不再是当前下载权威。
[`site/DOWNLOADS.md`](../site/DOWNLOADS.md) 仅保留 v0.1.4 迁移快照作为历史证据；当前版本化资产与
校验和均由发行仓库承载。
本地 `Rabbisir Open` 构建不是官方安装包。
