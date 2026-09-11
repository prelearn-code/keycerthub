# 参考资料与上游溯源

> **状态**：✅ 已成稿
> **实现阶段**：阶段 0

---

## 1. 为什么上游源码不纳入本仓库

本项目的三个主要参考项目均**不提交**到本仓库，原因：

| 原因 | 说明 |
|---|---|
| 许可证清晰 | 尤其 OpenBao 为 MPL-2.0（文件级 copyleft），vendor 第三方源码会让本仓库的许可证边界模糊 |
| 体积 | OpenSSL/GmSSL 源码各数十 MB，OpenBao 完整仓库约 380 MB |
| 语言统计失真 | 会把 GitHub 语言统计从 C++ 拉向 Go/C |
| 依赖管理 | 构建时应通过 vcpkg/系统包获取，而非源码树内副本 |

**替代方案**：上游源码放在仓库**同级目录**，仅供本地查阅与调试；溯源信息（本文档）留在仓库内。

---

## 2. 推荐的本地目录布局

```text
F:\study\work_study\
├── keycerthub/              ← 本仓库（Git 管理）
├── openssl/                 ← OpenSSL 源码（不提交）
├── gmssl/                   ← GmSSL 源码（不提交）
└── openbao-reference/       ← OpenBao 关键实现摘录，20 个文件（不提交）
```

> 注意：`keycerthub/` 是独立 Git 仓库，同级目录不在其版本控制范围内。
> **不要**在工作区根目录执行 `git init`，否则这些上游源码会被一并纳入。

---

## 3. 上游项目清单

| 项目 | 版本建议 | 许可证 | 上游地址 | 在本项目中的角色 |
|---|---|---|---|---|
| **OpenSSL** | 3.2+ | Apache-2.0 | https://github.com/openssl/openssl | 默认 Provider；AES/RSA/ECDSA/Ed25519/SM2/SM3/SM4 |
| **GmSSL** | 3.x | Apache-2.0 | https://github.com/guanzhi/GmSSL | 国密 Provider（独立进程）；SM2/SM3/SM4/SM9、国密证书 |
| **OpenBao** | main | MPL-2.0 | https://github.com/openbao/openbao | 架构参考：密钥层级、Seal、Transit 策略、审计模型 |

### 获取方式

```bash
# OpenSSL（如需源码级调试；日常构建用 vcpkg 即可）
git clone --depth 1 --branch openssl-3.2 https://github.com/openssl/openssl.git

# GmSSL
git clone --depth 1 https://github.com/guanzhi/GmSSL.git

# OpenBao（完整仓库较大，仅需参考时建议稀疏检出）
git clone --depth 1 --filter=blob:none --sparse https://github.com/openbao/openbao.git
cd openbao
git sparse-checkout set internal/vault/barrier internal/vault/seal sdk/helper/keysutil \
                       internal/builtin/logical/transit internal/vault/policy \
                       internal/vault/audit_broker.go sdk/physical
```

> **构建依赖不来自这些源码副本**。正式构建通过 `vcpkg.json` 锁定版本，
> 避免"本地能编译、CI 不能编译"。

---

## 4. OpenBao 参考点映射

下表说明本项目**参考了 OpenBao 的哪些设计**，以及对应本项目的哪个模块。
参考的是**设计思路**，不是代码移植。

| OpenBao 实现 | 参考的设计要点 | 本项目对应 |
|---|---|---|
| `internal/vault/barrier/aes_gcm.go` | 密文结构（Term + 版本字节 + Nonce + 密文 + Tag）；**路径作为 AAD** 防密文搬移；恒定时间比较；加密次数计数与自动轮换触发 | `crypto/envelope.h`、`security/master_key_manager.h` |
| `internal/vault/barrier/keyring.go` | 多 Term 版本共存；Active Term 加密、历史 Term 解密；加密次数上限（对齐 NIST SP 800-38D 的 2³²） | `domain/key/key_version.h`、`domain/key/rotation_policy.h` |
| `internal/vault/barrier/barrier.go` | `SecurityBarrier` 接口：把底层存储视为不可信，统一封装存储与加解密 | `docs/architecture.md` 信任边界；`repository/` 接口约束 |
| `internal/vault/seal/seal.go` | Seal 抽象为 `Wrapper` 接口，屏蔽 Shamir / KMS / HSM / Transit 差异 | `security/seal_provider.h` |
| `sdk/helper/keysutil/policy.go` | 密钥类型**能力矩阵**（加密/签名/派生/协商分别声明）；版本策略；密文模板 `vault:v{{version}}:`；RSA 参数显式化 | `provider/provider_capabilities.h`、`crypto/algorithm_params.h` |
| `internal/builtin/logical/transit/path_keys.go` | 密钥创建参数校验（类型、派生、收敛加密、可导出、明文备份、外部密钥） | `domain/key/key_policy.h` |
| `internal/builtin/logical/transit/path_encrypt.go` | 批量请求的**逐项错误模型**（单项失败不影响整体） | `application/crypto_service.h` 批量接口 |
| `sdk/physical/physical.go` | 存储接口最小化；`PermitPool` 并发许可池；HA 锁抽象；缓存失效钩子 | `repository/` 接口设计、`gateway/rate_limiter.h` |
| `internal/vault/policy/policy.go` | HCL 策略、能力位图、路径与段通配、**参数级约束**（allowed/denied/required_parameters）、模板化策略 | `domain/policy/` |
| `internal/vault/audit_broker.go` | 多后端广播；**"至少一个成功"**语义；panic 防护；请求/响应双阶段记录 | `application/audit_service.h`（本项目另加哈希链与 Merkle 锚定） |
| `internal/helper/builtinplugins/registry.go` | 三类后端注册表；废弃状态管理 | `provider/provider_registry.h` |

### 本项目有意做得不同的地方

| 方面 | OpenBao | 本项目 | 原因 |
|---|---|---|---|
| 审计完整性 | 多后端 + HMAC 脱敏 | 追加 **Hash Chain + Merkle 锚定** | 支持"某时间点后无篡改"的外部证明 |
| 国密支持 | 无 SM2/SM3/SM4/SM9 | GmSSL Provider（进程隔离） | 国密合规场景需求 |
| 多租户 | Namespace | 租户贯穿领域模型与仓储查询 | 租户隔离需在数据层强制 |
| 分布式共识 | 自研 Raft 集成 | 复用 PostgreSQL 主备 + advisory lock | 避免自研共识的风险与工作量 |
| 密码设备 | KMS Wrapper | PKCS#11 / SDF / KMIP 客户端 | 面向密码机对接场景 |

---

## 5. OpenSSL 与 GmSSL 参考点

### OpenSSL

| 参考内容 | 用途 |
|---|---|
| `EVP_*` 高层接口族 | 本项目**唯一允许**使用的密码调用方式（禁用已弃用的低层 RSA/EC 结构） |
| `EVP_PKEY_CTX_set_rsa_pss_saltlen` / `set_rsa_mgf1_md` | RSA-PSS/OAEP 参数显式化 |
| `cipher.NewGCMWithRandomNonce` 等价能力 | 障碍层随机 Nonce 生成 |
| `apps/openssl verify` | 证书链验证的**交叉验证工具**，用于兼容性测试 |
| `openssl asn1parse` | DER/ASN.1 结构排查 |

### GmSSL

| 参考内容 | 用途 |
|---|---|
| SM2 签名接口与默认 User ID | 明确本项目需**显式传递** User ID，不依赖默认值 |
| SM4 模式支持范围 | 决定能力协商策略：GCM 优先，CBC+HMAC-SM3 为基线 |
| 国密证书与 GMTLS | 阶段 8 的国密双证书与网关设计 |
| CLI 工具 | SM2/SM4 的跨库交叉验证 |

---

## 6. 许可证合规要求

### 强制规则

1. **禁止**将 OpenBao（MPL-2.0）源码复制进本仓库源码树
2. **禁止**在未确认许可证的情况下引入新的第三方代码
3. 引用上游代码逻辑时，**必须**在提交信息与代码注释中注明来源与许可证
4. 新增依赖必须同时更新 `vcpkg.json`、本文档和 `LICENSE` 依赖说明

### 许可证兼容性

| 上游 | 许可证 | 与本项目 Apache-2.0 的兼容性 |
|---|---|---|
| OpenSSL | Apache-2.0 | ✅ 兼容 |
| GmSSL | Apache-2.0 | ✅ 兼容 |
| OpenBao | MPL-2.0 | ⚠️ 文件级 copyleft：可独立使用，但**不修改、不复制**进本项目源码树即可安全参考 |

> 若将来确实需要复用某段 MPL-2.0 代码，必须：
> 1. 单独放入独立目录（如 `third_party/`）
> 2. 保留原许可证文件与版权头
> 3. 在该目录内放置说明文件，明确标注来源、版本、许可证
> 4. 在本项目 `LICENSE` 中说明该目录的例外

---

## 7. 相关文档

| 文档 | 关系 |
|---|---|
| [00-总体设计与实施路线图.md](00-总体设计与实施路线图.md) | 主设计文档 |
| [architecture.md](architecture.md) | 架构决策的上游依据 |
| [provider-design.md](provider-design.md) | Provider 抽象设计（参考 OpenBao 能力矩阵） |
| [compliance.md](compliance.md) | 算法清单与标准符合性 |
