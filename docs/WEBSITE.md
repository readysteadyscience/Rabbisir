# Public website boundary

The public GitHub Pages packaging root is [`site/`](../site). Its fixed-dark design and interaction
baseline come from the project owner's final historical Rabbisir website snapshot:

| Baseline file | Source SHA-256 | Public-candidate SHA-256 |
| --- | --- | --- |
| `rabbisir-site/index.html` | `cabcd17d40403a73b3eac517dfcc02e2df3a42b32a68093307f727080d1f9f28` | `c024ce612271d548157d230e2fb087d0c01a95d5ec60658d98f1d538b1cd676b` |
| `rabbisir-site/styles.css` | `468469c53cbd495c4677bca1301b9cd6b70a937f834053ef452a187e14b954af` | `f3a44a62c2a1eb3ff97c321bf9e3cc54d3c50fb4252bebd8c04fbabfe8417095` |
| `rabbisir-site/site.js` | `fe5fbcfe213e9a0d487b6f84fbf8beb6db0d6e10525d3625ddb869d19aca0ba6` | `fe5fbcfe213e9a0d487b6f84fbf8beb6db0d6e10525d3625ddb869d19aca0ba6` |

The public candidate preserves the baseline's black layout, typography, spacing, responsive rules,
language switch, contact dialog and reduced-motion behavior. Its narrowly reviewed public-boundary
adaptations are:

- remove the unlicensed DeepSeek graphic while keeping a prominent bilingual plain-text link to the
  official DeepSeek Harness repository;
- state in both languages that Rabbisir is independent, non-official and not affiliated with,
  sponsored by or endorsed by DeepSeek;
- use the byte-verified official X Brand Toolkit SVG for YelZap's X profile;
- use a clear `WeChat` / `微信` text button because no official redistributable WeChat logo byte and
  usage record was verified; the button still opens the project-owner-authorized creator-contact QR;
- replace the embedded Discord geometry with the already reviewed official Blurple symbol; and
- use the already authorized creator-avatar bytes rather than an unrecorded historical derivative.

Every packaged website asset and its digest is listed in
[`Legal/SITE_ASSET_MANIFEST.sha256`](../Legal/SITE_ASSET_MANIFEST.sha256), with ownership and usage
boundaries in [`Legal/BRAND_ASSETS.md`](../Legal/BRAND_ASSETS.md). DeepSeek graphics and unverified
WeChat graphics are forbidden from the capsule. Third-party marks and creator identity/contact
assets are not licensed under Rabbisir's MIT source license.

The deployed page path is the Pages artifact root. The public candidate moves the three reviewed
page files from their historical `rabbisir-site/` source directory to [`site/`](../site) and changes
only `index.html`'s relative dependency paths from the parent directory to that root. The stylesheet
and script remain byte-identical to the reviewed candidate, and no runtime rewriting is used. The
script stores only the language choice under `rabbisir-language`; it contains no fetch, analytics,
cookies, credentials, update path, payment path, or automatic external navigation.

Run the local and CI-equivalent gates before handing the site to open-source governance:

```sh
scripts/verify-pages-site.sh
scripts/verify-public-repository.sh
```

The Pages workflow is manual-only and refuses to deploy a ref other than `main`. A source push does
not authorize or trigger website publication.

## First-release publication gate

[`site/DOWNLOADS.md`](../site/DOWNLOADS.md) truthfully states that no official installation asset is
available. Do not deploy the page as a completed download surface while that remains true. The later
authorized release transaction must first produce and verify the signed, notarized and stapled
`Rabbisir 0.1.0 · r1.00` asset, then update only the download record with the real public Release URL,
filename, size, SHA-256 and acceptance evidence. `Rabbisir Open` is never an official downloadable
App.

## 中文边界

公开 GitHub Pages 打包根及页面入口都是 [`site/`](../site)。页面以项目所有者指定的最终黑底极简官网为
视觉与交互基线，只作上文列出的公开资产最小适配：移除 DeepSeek 图形但保留醒目的双语
文字上游链接和独立性声明；X 使用官方工具包原字节；微信因官方资源链未闭合而使用清晰
文字入口，并继续打开已授权公开的创作者联系二维码；Discord 与创作者头像使用项目中已经
登记的资产。

脚本只保存 `rabbisir-language` 语言选择，不包含分析、Cookie、凭据、更新、支付、自动外跳或
网络请求。当前没有官方安装包，网站不得伪造下载；正式下载必须等待官方首发资产真实产生并
完成签名、公证、Staple、Gatekeeper、公开 Release 与外网回读验证。
