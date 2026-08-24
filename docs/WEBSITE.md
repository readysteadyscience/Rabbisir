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
DMG as the primary installer and identifies the ZIP as the signed update archive. The page records
the supported platform, release, sizes, SHA-256 values, and canonical Release link. Versioned
filenames and the same audit facts remain in the source record
[`site/DOWNLOADS.md`](../site/DOWNLOADS.md). `Rabbisir Open` contributor builds are not official
downloadable Apps.

The primary DMG actions use the permanent GitHub path
`releases/latest/download/Rabbisir.dmg`. Every formal Release must publish its reviewed DMG under
that stable asset name, so the website always resolves to the newest formal installer without a site
source edit. The button label and accessibility text do not embed a version. A source commit does not
prove the asset is public and does not deploy Pages: the stable alias must resolve to the exact
reviewed DMG before deploying a website candidate. The release, sizes, and SHA-256 values remain on
the detail page; versioned filenames and the complete fact set remain in the auditable download
record. Generated Release metadata and the signed production update feed are added only in the
formal release transaction.

## 中文边界

公开 GitHub Pages 打包根及页面入口均位于 [`site/`](../site)。网站保留黑底响应式布局、双语切换、
联系弹窗和减少动态效果支持。DeepSeek 仅使用醒目的双语文字链接及独立性声明；X、Discord、
Rabbisir 标识、创作者头像和微信联系二维码均遵守上文列出的公开资产用途与许可边界。

脚本只保存 `rabbisir-language` 语言选择，不包含分析、Cookie、凭据、更新、支付或自动外跳逻辑。
官网面向浏览器的下载页为 [`site/download.html`](../site/download.html)：DMG 是主要安装包，ZIP
明确标记为签名更新归档。页面记录支持平台、版本、大小、SHA-256 和 GitHub Release 链接；
版本化文件名及相同审计事实保留在 [`site/DOWNLOADS.md`](../site/DOWNLOADS.md) 源记录中。本地
`Rabbisir Open` 构建不是官方安装包。

主 DMG 下载操作固定使用 GitHub 的永久路径 `releases/latest/download/Rabbisir.dmg`。每次正式
Release 都必须以同一个 `Rabbisir.dmg` 资产名发布经审查的 DMG，使官网无需修改源码即可始终
解析到最新正式安装包；按钮及其无障碍文本不嵌入版本号。源码提交不代表该稳定资产已经公开，
也不会部署 Pages；部署网站候选前必须回读确认稳定入口指向本次经审查的准确 DMG。版本、大小
和 SHA-256 继续显示在详情页，版本化文件名与完整事实集保留在可审计下载记录中；生成的 Release
元数据和已签名生产更新源仍只在正式发布事务中加入。
