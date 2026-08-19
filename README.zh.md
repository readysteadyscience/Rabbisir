# Rabbisir

[English](README.md) | 中文

Rabbisir 是面向 DeepSeek 模型的原生 macOS 工作台。空间工作区、项目与会话导航、对话流、输入区、设置、文档工作台、菜单和辅助功能均由 SwiftUI 与 AppKit 承载。

Rabbisir 是独立产品，与 DeepSeek 不存在隶属、赞助或背书关系。App 使用兼容的 MIT 许可 DeepSeek Harness 运行时快照；来源、许可和兼容记录保存在 [`Legal/`](Legal/README.md)。

## 仓库范围

本仓库只包含构建和测试 Rabbisir macOS App 所需的内容：

- SwiftPM App 与原生测试套件；
- Rabbisir 自有品牌资源；
- App 私有上游运行时的小型启动器、版本清单与可复现来源契约；
- 公开的开发、架构、隐私和法律文档。

本仓库也包含公开 GitHub Pages 官网的最小静态源码与手动部署契约。它不包含独立 Web App、
CLI 产品、上游示例、上游开发工具或内部产品计划。生成的 Node 与运行时载荷从独立的兼容
上游检出或构建产物暂存，并由 Git 忽略。

公开 Package 是可复现的开源产品变体，保留创作者归属、Discord 社区入口、公开帮助、
许可证与 GitHub 反馈链接；不包含应用内更新器、自愿支持界面或主题/壁纸占位。
官方分发新增能力只能由单独摘要签收的私有 overlay 注入；缺少 overlay 或必要配置时，
受控生产入口会安全拒绝构建。

## 环境要求

- macOS 14 或更高版本。
- `/Applications/Xcode.app` 中的 Xcode。
- 启动完整 App 所需的已暂存运行时资源。

## 构建与测试

```sh
scripts/build-fresh-public-product.sh RabbisirOpen debug
scripts/test-public-swiftpm.sh
scripts/build-and-run-open.sh --verify-first-run
scripts/verify-pages-site.sh
```

公开 Package 只暴露 `Rabbisir Open`。构建运行脚本只会在专用临时目录创建未签名 App，
使用独立 Bundle ID `com.rabbisir.desktop.open`，隔离偏好与运行时数据，验证首次配置界面就绪，
并在退出时移除临时 App 与数据。Git 树不得包含已构建 App、DMG、ZIP 或其他安装包。
干净检出的 CI 只验证源码边界与格式。完整 App 验收须先按文档暂存带收据的运行时输入，
再运行 `scripts/verify-public-candidate.sh --verify-first-run`；运行时载荷本身仍不得进入 Git。

维护者先从精确的官方源码版本重建带来源收据的载荷，再进行暂存：

```sh
scripts/rebuild-vendor-runtime.sh \
  <official-upstream-checkout> \
  <node-distribution-root> \
  <verified-pnpm-archive> \
  <new-output-root>
scripts/stage-vendor-runtime.sh <receipted-runtime-carrier-root> <node-distribution-root>
```

公开的[运行时来源契约](RuntimeProvenance/README.md)固定并验证源码、补丁、工具链与规范输出清单。
用户不需要启动 localhost 服务，也不使用 Web 入口。

## 文档

- [架构](docs/ARCHITECTURE.md)
- [开发](docs/DEVELOPMENT.md)
- [隐私与本地数据](docs/PRIVACY.md)
- [资源归属](ASSETS.md)
- [上游兼容记录](Legal/UPSTREAM.md)
- [运行时来源与可复现构建](RuntimeProvenance/README.md)
- [公开官网边界](docs/WEBSITE.md)

本地构建命令不会执行任何外部仓库或正式分发操作。
