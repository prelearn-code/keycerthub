# KeyCertHub

> 企业级密钥与证书管理系统 — 密钥生命周期、证书生命周期、密码运算服务、协议互操作、多租户、高可用、审计合规

[![状态](https://img.shields.io/badge/状态-骨架阶段-orange)]()
[![版本](https://img.shields.io/badge/版本-v0.0.1--skeleton-blue)]()
[![语言](https://img.shields.io/badge/C%2B%2B-17-blue)]()
[![许可证](https://img.shields.io/badge/许可证-Apache--2.0-green)]()

---

## 项目简介

KeyCertHub 是一个使用 **C++17 + OpenSSL/GmSSL** 构建的密钥与证书管理系统，覆盖：

- **密钥管理（KMS）**：生成、导入（BYOK）、版本轮换、生命周期状态机、信封加密、备份恢复
- **证书管理（PKI）**：多级 CA、CSR、受控 Profile、签发/续期/重签/吊销、CRL/Delta CRL、OCSP
- **密码运算服务**：AES/SM4 加解密、RSA/SM2 签名验签、摘要、HMAC、随机数、数据密钥
- **协议互操作**：KMIP、EST、ACME、SCEP、OCSP、PKCS#11、GMTLS
- **安全与治理**：Seal 分层密钥保护、多租户隔离、策略引擎、防篡改审计
- **运维与交付**：高可用部署、指标监控、备份恢复、合规材料

设计目标：**数据库被拖库后攻击者仍无法获得密钥材料**。

---

## 当前状态

> ⚠️ **本仓库处于骨架阶段（v0.0.1），所有功能代码均为占位符，尚不可运行。**

已完成：

- [x] 完整目录结构（85 目录）
- [x] 构建系统骨架（CMake + Presets + vcpkg）
- [x] 接口占位符（66 个头文件、41 个源文件）
- [x] 文档骨架（23 个设计文档）
- [x] 配置示例、代码风格、许可证声明

未开始：

- [ ] 密码运算实现
- [ ] 密钥管理实现
- [ ] PKI 实现
- [ ] 服务与协议实现

进度详见 [`docs/roadmap.md`](docs/roadmap.md)。

---

## 快速开始

### 前置条件

| 依赖 | 版本 | 说明 |
|---|---|---|
| 操作系统 | Ubuntu 22.04 / 24.04 LTS | **一等目标平台** |
| 编译器 | GCC 12+ 或 Clang 15+ | 需 C++17 |
| CMake | 3.24+ | 使用 Presets |
| Ninja | 1.10+ | 构建后端 |
| vcpkg | 最新 | 依赖管理 |
| OpenSSL | 3.x | 国际算法 |
| GmSSL | 3.x | 国密算法（阶段 5） |

> **平台说明**：本项目以 Linux 为唯一一等目标平台。Windows 仅建议作为编辑环境，
> 或使用 WSL2（须将仓库放在 WSL 文件系统内，不要放在 `/mnt/c` 或 `/mnt/f`）。
> 原因：`mlock`、`setrlimit`、文件权限、Unix Socket、systemd 等行为在 Windows 上
> 无法正确验证。

### 构建

```bash
# 设置 vcpkg 路径
export VCPKG_ROOT=/opt/vcpkg

# 配置与构建
cmake --preset debug
cmake --build --preset debug -j

# 运行
./build/debug/keycerthub
```

### 测试

```bash
ctest --preset debug --output-on-failure
```

### 消毒器构建

```bash
cmake --preset asan && cmake --build --preset asan -j   # ASan + UBSan
cmake --preset tsan && cmake --build --preset tsan -j   # TSan
```

---

## 项目结构

```text
keycerthub/
├── include/keycerthub/      公共头文件（接口层）
│   ├── api/                 REST/gRPC 控制器
│   ├── gateway/             认证、租户、限流、审计钩子
│   ├── application/         应用服务编排
│   ├── domain/              领域模型（key/certificate/secret/tenant/policy/audit）
│   ├── crypto/              SecureBuffer、Envelope、算法参数
│   ├── provider/            CryptoProvider 抽象与能力协商
│   ├── protocol/            KMIP / EST / ACME / OCSP
│   ├── repository/          仓储接口
│   └── security/            Seal、Master Key、Token、授权
├── src/                     实现（与 include 同构）
├── providers/               独立 Provider 进程（GmSSL、PKCS#11）
├── sdk/                     C++ / Go / Java / Python SDK
├── cli/  agent/  ui/        工具链
├── migrations/              SQLite / PostgreSQL schema 迁移
├── tests/                   单元/集成/兼容/安全/模糊/混沌/性能
├── scripts/                 演示、兼容性、基准脚本
├── docs/                    设计文档（23 篇）
├── deploy/                  Docker / Helm / systemd
└── config/                  配置示例
```

---

## 分层架构

```text
接入层      REST | gRPC | CLI | Web UI | KMIP | EST/ACME | OCSP
             |
网关层      认证 | 授权 | 限流 | 校验 | 租户解析 | 审计前置
             |
应用层      KeyService | CertificateService | CryptoService | SecretService
             |
领域层      状态机 | 策略 | 版本 | ACL | 租约 | 合规规则
             |
Provider层  OpenSSL | GmSSL(远程) | PKCS#11 | MockHSM | KMIP
             |
存储层      Seal -> MasterKey -> 加密的密钥材料
             |
持久化      PostgreSQL / SQLite | 审计日志 | 信任库
```

**六条不可违反的规则**：

1. Controller 不直接调用 OpenSSL/GmSSL
2. Service 只持有 `KeyHandle` / `SecureBuffer`
3. Domain 层不依赖 HTTP 与数据库实现
4. 私钥与对称密钥落库前必须加密
5. 敏感操作必须经过 认证 → 授权 → 策略 → 审计
6. 跨租户访问一律拒绝并记录审计

---

## 密钥保护模型

```text
Seal Key                来源：文件 / HSM / 口令 / Shamir 分片 / 云 KMS
    |
    v
Master Key (Root KEK)   加密后落库；用于加密所有密钥材料
    |
    v
Managed Keys            KEK / DEK / 签名密钥 / CA 私钥
    |
    v
Per-request DEK         仅以 Wrapped 形式随业务密文保存
```

**关键约束**：Master Key 绝不直接用于业务数据加密；密钥材料落库时 AAD 绑定
`key_id ‖ key_version ‖ algorithm ‖ purposes ‖ tenant_id`，防止密文搬移攻击。

---

## 技术栈

| 类别 | 选型 |
|---|---|
| 语言 | C++17 |
| 构建 | CMake 3.24+ / Ninja / vcpkg |
| 密码库 | OpenSSL 3.x、GmSSL 3.x（进程隔离） |
| REST | Drogon |
| gRPC | gRPC C++（阶段 4+） |
| 数据库 | SQLite（开发）/ PostgreSQL（生产） |
| 日志 | spdlog |
| 配置 | yaml-cpp |
| 测试 | GoogleTest、Google Benchmark、libFuzzer |
| 工具 | clang-format、clang-tidy、ASan/UBSan/TSan |

---

## 实施路线图

| 阶段 | 周数 | 版本 | 主题 |
|---|---:|---|---|
| 0 | 2 | v0.01 | 工程奠基 |
| 1 | 3 | v0.1 | 密码核心与 Provider |
| 2 | 4 | v0.5 | 密钥管理与存储保护 |
| 3 | 5 | v0.8 | PKI 完整化 ★ |
| 4 | 4 | v1.0 | 服务化、多租户与策略 |
| 5 | 5 | v1.2 | 互操作与密码设备 |
| 6 | 4 | v1.5 | 高可用与运维成熟 |
| 7 | 4 | v1.8 | 工具链与生态 |
| 8 | 5 | v2.0 | 前沿密码与合规 |

★ = 求职演示最低标准，建议在此冻结并录制演示视频。

详见 [`docs/roadmap.md`](docs/roadmap.md)。

---

## 文档

| 文档 | 内容 |
|---|---|
| [总体设计与实施路线图](docs/00-总体设计与实施路线图.md) | **主设计文档**（210 项功能矩阵） |
| [docs/architecture.md](docs/architecture.md) | 系统架构 |
| [docs/threat-model.md](docs/threat-model.md) | 威胁模型 |
| [docs/crypto-design.md](docs/crypto-design.md) | 密码设计 |
| [docs/key-management.md](docs/key-management.md) | 密钥管理 |
| [docs/certificate-management.md](docs/certificate-management.md) | 证书管理 |
| [docs/api.md](docs/api.md) | 接口契约 |
| [docs/deployment.md](docs/deployment.md) | 部署文档 |
| [docs/README.md](docs/README.md) | 文档索引 |

---

## 安全说明

- 本项目演示用的 CA **不得用于生产环境**；生产 Root CA 必须离线或托管 HSM
- Seal Key 丢失且无分片备份时，数据**不可恢复**（设计特性）
- 不承诺绝对的内存安全清除
- 漏洞报告请遵循 [`SECURITY.md`](SECURITY.md)，勿开公开 Issue

---

## 参考资料

本项目的设计参考了以下上游项目。为保持许可证清晰，**上游源码不纳入本仓库**：

| 项目 | 用途 | 许可证 | 上游 |
|---|---|---|---|
| OpenSSL | 国际算法主 Provider | Apache-2.0 | https://github.com/openssl/openssl |
| GmSSL | 国密算法 Provider | Apache-2.0 | https://github.com/guanzhi/GmSSL |
| OpenBao | 密钥层级、Seal、Transit 策略的架构参考 | MPL-2.0 | https://github.com/openbao/openbao |

详细的参考点映射与许可证说明见 [`docs/references.md`](docs/references.md)。

---

## 许可证

Apache License 2.0（待最终确认，见 [`LICENSE`](LICENSE)）

Copyright (c) 2026 KeyCertHub Contributors
