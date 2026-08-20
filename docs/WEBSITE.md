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

The site is self-contained. Its script stores only the language choice under `rabbisir-language`; it
contains no analytics, cookies, credentials, updater logic, payment path, or automatic external
navigation.

Run the local and CI-equivalent gates after website-source changes:

```sh
scripts/verify-pages-site.sh
scripts/verify-public-repository.sh
```

## Downloads

The browser-facing download page is [`site/download.html`](../site/download.html). It presents the
DMG as the primary installer and identifies the ZIP as the signed update archive. Filenames,
supported platform, sizes, SHA-256 values, and the canonical Release link are recorded in the page
and in the auditable source record [`site/DOWNLOADS.md`](../site/DOWNLOADS.md). `Rabbisir Open`
contributor builds are not official downloadable Apps.

## 中文边界

公开 GitHub Pages 打包根及页面入口均位于 [`site/`](../site)。网站保留黑底响应式布局、双语切换、
联系弹窗和减少动态效果支持。DeepSeek 仅使用醒目的双语文字链接及独立性声明；X、Discord、
Rabbisir 标识、创作者头像和微信联系二维码均遵守上文列出的公开资产用途与许可边界。

脚本只保存 `rabbisir-language` 语言选择，不包含分析、Cookie、凭据、更新、支付或自动外跳逻辑。
官网面向浏览器的下载页为 [`site/download.html`](../site/download.html)：DMG 是主要安装包，ZIP
明确标记为签名更新归档。GitHub Release 链接、文件名、大小和 SHA-256 同时记录在该页面与
可审计的 [`site/DOWNLOADS.md`](../site/DOWNLOADS.md) 源记录中；本地 `Rabbisir Open` 构建不是
官方安装包。
