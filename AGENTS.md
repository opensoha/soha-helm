# Soha Helm 仓库入口

- 本仓负责 Helm charts 和仓库索引；chart 消费已发布镜像和配置契约，原始部署清单归属相应运行时仓库。
- 在 OpenSoha 多仓工作区中读取 `../AGENTS.md` 一次；独立克隆时使用本仓规则，不要求初始化相邻仓库或规划工具。
- Chart 实现或审查按需使用 [soha-helm](.agents/skills/soha-helm/SKILL.md)。仅在行为涉及对应层时同步 values、schema、templates 与文档，保留 secrets 和升级兼容边界。
- 迭代选择相关 lint、render 或既有渲染断言；完整验证入口为 `make verify`，发布条件以 [Helm 仓库流程](.github/workflows/helm-repo.yml) 为准。
- 文档和技能改动只检查内容、链接与差异；相关代码和环境未变化时复用成功验证，保留用户未提交改动。
