# 上游兼容记录

[English](UPSTREAM.md) | 中文

Rabbisir 使用 MIT 许可 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 项目的源码和运行时组件。Rabbisir 是独立产品，与 DeepSeek 不存在隶属、赞助或背书关系。

当前兼容基线是上游提交 `47f943859bef60e4160492346772ded9b24f765a`（tree
`f904efab9ef435201d6ba4da88a34d6366568272`），运行时报告版本为 `0.1.0-rc.5`。
[`LICENSE.upstream.txt`](LICENSE.upstream.txt) 保留上游许可证，
[`THIRD_PARTY_NOTICES.upstream.md`](THIRD_PARTY_NOTICES.upstream.md) 保留该源码基线生成的依赖声明。

Rabbisir 仓库不包含上游 monorepo，只包含原生 App、兼容桥、受版本控制的运行时启动器与
清单，以及 [`RuntimeProvenance`](../RuntimeProvenance/README.md) 中可审计的补丁集与构建契约。
生成运行时载荷不进入 Git。用于比较或重新暂存的官方源码检出必须位于独立目录或仓库。

兼容所需的上游包标识、RPC 方法、事件名、设置命名空间、持久 ID、wire 字段和存储格式保持不变。Rabbisir 自有文件、Swift 类型、UI、诊断、脚本和日志使用 Rabbisir 或中性运行时命名。

更新基线时，维护者在独立检出中比较目标上游版本，刷新受版本控制的兼容补丁与来源契约，
通过 `scripts/rebuild-vendor-runtime.sh` 重建，再由 `scripts/stage-vendor-runtime.sh` 暂存已验证
收据，并运行原生测试与真实 App 工作流。上游更新只有完成兼容性审查与验证后，才会进入
公开发布的 Rabbisir 版本。
