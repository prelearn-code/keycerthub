# KeyCertHub 文档索引

本目录是 KeyCertHub 的设计与交付文档。**主设计文档**位于仓库上层：
[`../../密钥与证书管理系统总体设计与实施路线图.md`](../../密钥与证书管理系统总体设计与实施路线图.md)

---

## 文档状态说明

| 标记 | 含义 |
|---|---|
| ✅ | 已成稿 |
| 🚧 | 骨架已建，内容待补 |
| ⬜ | 尚未创建 |

绝大多数文档当前为 🚧 占位符状态，会随实施阶段逐步补齐。

---

## 设计文档

| 文档 | 内容 | 对应主文档章节 | 阶段 | 状态 |
|---|---|---|---|:--:|
| [architecture.md](architecture.md) | 系统架构、分层职责、数据流、信任边界 | 第五章 | 0 | ✅ |
| [threat-model.md](threat-model.md) | 资产、攻击者假设、威胁枚举与缓解 | 第一章、第二十五章 | 0 | 🚧 |
| [crypto-design.md](crypto-design.md) | 算法参数、格式规范、随机数要求 | 第八、九章 | 1 | ✅ |
| [key-management.md](key-management.md) | 密钥模型、状态机、轮换、分层保护 | 第六、七章 | 2 | ✅ |
| [certificate-management.md](certificate-management.md) | CA 层级、Profile、签发、吊销、CRL | 第十章 | 3 | 🚧 |
| [provider-design.md](provider-design.md) | Provider 接口、能力协商、设备对接 | 7.7、十一章 | 1 | 🚧 |
| [protocol-interop.md](protocol-interop.md) | KMIP / EST / ACME / OCSP / PKCS#11 | 十一章 | 5 | 🚧 |
| [multi-tenancy.md](multi-tenancy.md) | 租户模型、隔离、策略引擎 | 十二章 | 4 | 🚧 |
| [secret-management.md](secret-management.md) | KV 秘密、租约、动态凭据 | 十三章 | 7 | 🚧 |
| [high-availability.md](high-availability.md) | 主备架构、选举、备份恢复、DR | 十四章 | 6 | 🚧 |
| [database-schema.md](database-schema.md) | 15 张表的完整 schema 与迁移 | 十五章 | 2 | 🚧 |
| [api.md](api.md) | REST/gRPC 接口契约 | 十六章 | 1–4 | 🚧 |
| [error-codes.md](error-codes.md) | 错误码手册与信息原则 | 十九章 | 1 | 🚧 |

## 质量与交付文档

| 文档 | 内容 | 对应主文档章节 | 阶段 | 状态 |
|---|---|---|---|:--:|
| [testing.md](testing.md) | 测试分层、门禁、覆盖率要求 | 二十四章 | 1 | 🚧 |
| [compatibility-report.md](compatibility-report.md) | OpenSSL ↔ GmSSL 兼容矩阵结果 | 24.2 | 5 | 🚧 |
| [performance-report.md](performance-report.md) | 基准与压测结果、瓶颈分析 | 24.3 | 6 | 🚧 |
| [deployment.md](deployment.md) | 安装、配置、解封、升级、备份 | 二十二章 | 4 | 🚧 |
| [operations.md](operations.md) | 巡检、告警、故障排查、演练 | 二十一、二十二章 | 6 | 🚧 |
| [user-manual.md](user-manual.md) | CLI 与 API 使用示例 | 二十一章 | 4 | 🚧 |
| [compliance.md](compliance.md) | GM/T、等保、密评材料清单 | 二十三章 | 8 | 🚧 |
| [roadmap.md](roadmap.md) | 阶段 0–8 实施路线图与裁剪方案 | 二十六章 | 0–8 | 🚧 |
| [glossary.md](glossary.md) | 术语表 | 附录 | 0 | 🚧 |
| [adr/README.md](adr/README.md) | 架构决策记录 | 二十八章 | 0 | 🚧 |

---

## 阅读路径建议

### 想快速了解项目

```text
README.md（仓库根）
  -> docs/architecture.md
  -> docs/roadmap.md
  -> 主设计文档 第二章（210 项功能矩阵）
```

### 要参与开发

```text
docs/architecture.md         理解分层与禁止事项
  -> docs/crypto-design.md   密码参数与格式约定
  -> docs/key-management.md  密钥模型与状态机
  -> docs/api.md             接口契约
  -> CONTRIBUTING.md         提交规范
```

### 关注安全

```text
docs/threat-model.md
  -> docs/crypto-design.md
  -> docs/key-management.md（第六章：分层密钥保护）
  -> 主设计文档 第二十五章（安全基线检查表）
```

### 关注交付与运维

```text
docs/deployment.md
  -> docs/operations.md
  -> docs/high-availability.md
  -> docs/compliance.md
```

---

## 文档维护约定

1. **单一事实来源**：功能范围与优先级以主设计文档第二章的功能矩阵为准，本目录文档不重复定义范围
2. **代码同步**：涉及接口、格式、参数的改动必须同步更新对应文档
3. **占位符规范**：未完成文档保留标题与章节骨架，标注状态与所属阶段，不写"待补充"以外无意义内容
4. **不隐瞒限制**：已知限制、未实现功能、Demo 与生产的差异必须明确写出
