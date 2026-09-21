# Soha Helm 仓库入口

- 本仓负责 Helm charts 和仓库索引；chart 消费已发布镜像和配置契约，原始部署清单归属相应运行时仓库。
- 在 OpenSoha 多仓工作区中读取 `../AGENTS.md` 一次；独立克隆时使用本仓规则，不要求初始化相邻仓库或规划工具。
- Chart 实现或实质审查前读取 [soha-helm](.agents/skills/soha-helm/SKILL.md) 及本次相关参考，不只依赖技能自动匹配。只加载涉及的 chart、运行时配置和验证入口；已读且未变化的内容可复用。
- 仅在行为涉及对应层时同步 values、schema、templates 与文档，保留 secrets 和升级兼容边界。
- 迭代选择相关 lint、render 或既有渲染断言；完整验证入口为 `make verify`，发布条件以 [Helm 仓库流程](.github/workflows/helm-repo.yml) 为准。
- 文档和技能改动只检查内容、链接与差异；相关代码和环境未变化时复用成功验证，保留用户未提交改动。

## 变更与验收边界

- 修改前明确受影响 chart、配置真实源、支持的安装/升级场景和需保持的 selector、Secret 引用及 rollout 行为；不能为单个 chart 修复顺手改变其他 chart 默认值。
- 当前渲染结果用于核实实现，不证明它符合有效配置契约。发现文档、schema 与运行时冲突时说明依据，不复制其他 chart 的历史偏差。
- 对受影响分支补充正反例渲染断言；保留现有门禁，不以改宽 schema、忽略失败或覆盖基线通过检查。
- 验证记录包含 chart 提交/版本、实际镜像版本或摘要、values 场景及命令结果。lint/render 通过不等于安装或升级已验证，缺少集群的场景明确列为未运行。
- 仅按明确用户授权提交、推送或发布；本仓规则与任务记录本身不授权发布，也不要求修改无关 sibling 仓库。
