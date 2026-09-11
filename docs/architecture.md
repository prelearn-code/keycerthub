# 系统架构设计

> **状态**：✅ 已成稿
> **设计依据**：`00-总体设计与实施路线图.md` 第五章
> **实现阶段**：阶段 0

---

## 概述与目标

KeyCertHub 采用**分层架构 + 端口适配器（Ports & Adapters）**风格。核心架构目标：

| 目标 | 架构手段 |
|---|---|
| 密码库可替换 | Provider 抽象层，业务层不接触 OpenSSL API |
| 数据库可替换 | Repository 接口，SQLite/PostgreSQL 双实现 |
| 密码设备可接入 | Provider 能力协商 + 进程外 Provider |
| 数据库被拖库不致命 | Seal → MasterKey → 材料加密落库 |
| 权限可治理 | 网关统一鉴权 + 策略引擎 + 资源级 ACL |
| 多租户可隔离 | 租户贯穿领域模型与仓储查询条件 |
| 行为可追溯 | 全链路审计 + 防篡改哈希链 |
| 接口可扩展 | 接入层协议适配器收敛到内部模型 |

---

## 分层架构

```text
+------------------------------------------------------------------+
| 接入层 Access                                                     |
| REST(HTTPS) | gRPC | CLI | Web UI | KMIP | EST/ACME | OCSP        |
+-------------------------------+----------------------------------+
                                |
+-------------------------------v----------------------------------+
| 网关层 Gateway                                                    |
| 认证 | 授权 | 限流 | 请求校验 | 请求ID | 租户解析 | 审计前置       |
+-------------------------------+----------------------------------+
                                |
+-------------------------------v----------------------------------+
| 应用层 Application                                                |
| KeyService | CertificateService | CryptoService | SecretService   |
| TenantService | AuditService | BackupService | PolicyService      |
+-------------------------------+----------------------------------+
                                |
+-------------------------------v----------------------------------+
| 领域层 Domain                                                     |
| KeyPolicy | KeyVersion | StateMachine | CertProfile | CertLifecycle|
| ACL | PolicyEngine | Lease | TenantNamespace | Compliance         |
+-------------------------------+----------------------------------+
                                |
+-------------------------------v----------------------------------+
| 密码抽象层 Provider                                               |
| OpenSSLProvider | GmSSLProvider(remote) | PKCS11Provider          |
| MockHsmProvider | KmipClientProvider                               |
+-------------------------------+----------------------------------+
                                |
+-------------------------------v----------------------------------+
| 受保护存储 Protected Storage                                      |
| SealProvider -> MasterKey -> Encrypted Key/Cert Material          |
+-------------------------------+----------------------------------+
                                |
+-------------------------------v----------------------------------+
| PostgreSQL / SQLite | 备份存储 | 审计日志 | 信任库                 |
+------------------------------------------------------------------+
```

### 代码目录映射

| 架构层 | 头文件目录 | 实现目录 |
|---|---|---|
| 接入层 | `include/keycerthub/api/` | `src/api/` |
| 网关层 | `include/keycerthub/gateway/` | `src/gateway/` |
| 应用层 | `include/keycerthub/application/` | `src/application/` |
| 领域层 | `include/keycerthub/domain/` | `src/domain/` |
| 密码抽象层 | `include/keycerthub/provider/` | `src/provider/` |
| 协议适配 | `include/keycerthub/protocol/` | `src/protocol/` |
| 持久化 | `include/keycerthub/repository/` | `src/repository/` |
| 安全设施 | `include/keycerthub/security/` | `src/security/` |
| 密码原语 | `include/keycerthub/crypto/` | `src/crypto/` |

---

## 分层职责与禁止事项

| 层 | 职责 | 禁止事项 |
|---|---|---|
| 接入层 | 协议适配、参数解析、响应序列化 | 不含业务逻辑；不访问数据库 |
| 网关层 | 认证、授权、限流、租户解析、审计前置 | 不直接访问数据库；不实现密码运算 |
| 应用层 | 业务编排、事务边界、跨领域协调 | 不保存裸 `EVP_PKEY*`；不直接调用 OpenSSL |
| 领域层 | 状态机、策略规则、版本约束、不变量保护 | 不依赖 HTTP、数据库、密码库实现 |
| Provider | 算法调用、格式转换、设备差异屏蔽 | 不做业务判断；不访问数据库 |
| 协议适配 | 协议报文 ↔ 内部模型转换 | **禁止绕过网关直接调用 Service** |
| 仓储层 | 持久化、查询、事务 | 不做密码运算；不向应用层返回明文材料 |
| 安全设施 | Seal、MasterKey、Token、授权判定 | 不泄露密钥材料；不写日志 |

---

## 不可违反的规则

### 规则 1：接入层不直接调用密码库

```cpp
// ❌ 禁止
std::string ApiHandler::encrypt(const std::string& plaintext) {
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    // ...
}

// ✅ 正确
Result<Envelope> CryptoController::encrypt(const EncryptRequest& req) {
    return crypto_service_.encrypt(req);
}
```

### 规则 2：应用层只持有句柄或安全缓冲区

```cpp
class CryptoService {
    // ❌ 禁止成员： EVP_PKEY* private_key_;
    // ✅ 允许成员： KeyHandle、SecureBuffer
};
```

### 规则 3：领域层不依赖基础设施

`domain/` 下代码不得 `#include` 任何 OpenSSL、Drogon、数据库头文件。
需要密码能力时通过 Provider 接口注入（依赖倒置）。

### 规则 4：密钥材料落库前必须加密

仓储层写入 `key_versions.encrypted_material` 前，必须已由 `MasterKeyManager` 加密。
仓储接口**不得接受明文密钥材料**作为参数类型。

```cpp
// 数据类型层面强制：只接受密文
void KeyRepository::saveVersion(const KeyVersionRecord& record);
// record.encrypted_material 语义上必须是密文
```

### 规则 5：敏感操作四步走

```text
认证 → 授权 → 策略校验 → 审计

任一步失败或无法判定，一律拒绝（fail-closed）
```

### 规则 6：跨租户访问一律拒绝

```text
1. 所有仓储查询必须携带 tenant_id 过滤条件
2. 领域层与策略层双重校验 tenant_id 一致性
3. 跨租户访问记录审计并触发告警
```

---

## 关键数据流

### 加密流程

```text
Client
  | POST /api/v1/{tenant}/crypto/encrypt
  v
[接入层]  解析请求、字段校验
  v
[网关层]  认证 → 租户解析 → 授权 → 限流 → 生成 request_id
  v
[CryptoService] 编排
  |-- → [KeyManager] 取 KeyHandle
  |        |-- 校验 tenant_id 匹配
  |        |-- 校验密钥状态 = ACTIVE
  |        |-- 校验 purposes 含 Encrypt
  |        |-- 校验算法与 Provider 能力
  |        `-- 递增 usage_count（事务）
  |-- → [Provider] 执行加密
  |        `-- OpenSSL EVP_EncryptInit_ex2 / Update / Final_ex
  |-- → [Envelope] 组装自描述密文
  `-- → [AuditService] 记录审计
  v
Client ← Envelope { format_version, algorithm, key_id, key_version,
                    tenant_id, nonce, ciphertext, tag }
```

### 密钥创建流程

```text
Client → [API] → [Gateway] → [KeyService]
    |-- → [Provider] generateKey(spec) → KeyMaterial(SecureBuffer)
    |-- → [MasterKeyManager] 加密材料
    |        `-- AES-256-GCM，AAD = tenant‖key_id‖version‖alg‖purposes
    |-- → [KeyRepository] 事务写入
    |        |-- managed_keys   （元数据，明文）
    |        `-- key_versions   （材料，密文）
    `-- → [AuditService]
    v
KeyInfo（不含任何密钥材料）
```

### 证书签发流程

```text
Client → [API] → [Gateway] → [CertificateService]
    |-- 解析 CSR → 验证自签名
    |-- 加载 Profile → 校验 Subject/SAN/KU/EKU/有效期
    |-- 生成唯一序列号（CSPRNG，≥64 bit 熵）
    |-- → [KeyManager] 取 CA 私钥 KeyHandle
    |        `-- 校验 purposes 含 IssueCertificate
    |-- → [Provider] issueCertificate(...)
    |-- → [CertificateRepository] 持久化
    `-- → [AuditService]
    v
证书 PEM + 完整证书链
```

### 动态凭据流程

```text
Client → [API] → [Gateway] → [SecretService]
    |-- 校验租约策略与配额
    |-- → 后端（DB / 云 / SSH CA）创建临时凭据
    |-- → [LeaseManager] 创建租约，绑定撤销回调
    `-- → [AuditService]
    v
凭据 + lease_id + TTL
    |
（到期自动撤销，调用后端清理）
```

---

## 信任边界

| 边界 | 信任级别 | 依据 |
|---|---|---|
| Client → 接入层 | **不信任** | 必须认证、授权、参数校验、限流 |
| 进程内各层 | 信任 | 参数已在上层校验 |
| Provider 进程 | **有条件信任** | 需 mTLS + 输入校验 + 超时控制 |
| 数据库 | **不信任** | 视为随时可能被拖库 |
| 备份存储 | **不信任** | 备份包必须加密 |
| 审计日志 | **不信任** | 需哈希链证明完整性 |
| KMS / HSM | 信任但需容错 | 可能超时、不可用、返回错误 |
| 时间源 | 弱信任 | 时间回拨影响证书有效期与租约判定 |

### 「数据库不可信」的具体含义

攻击者获得数据库完整读写权限后：

| 能获得 | 不能获得 |
|---|---|
| 密钥元数据（ID、算法、用途、状态、版本） | 密钥材料明文（已加密） |
| 密钥材料密文（AES-256-GCM） | 解密所需 Master Key |
| 证书、CSR、CRL | CA 私钥明文 |
| 租户、策略、配额配置 | 审计链 HMAC 密钥 |
| 审计事件（脱敏后） | 用户 Token 明文（仅存哈希） |
| 业务密文（若也在同库） | 业务明文 |

**结论**：单点拖库不导致密钥泄漏。但攻击者仍可观察元数据、破坏可用性，
或结合其他漏洞（如读取到 Master Key 文件）升级攻击——因此 Seal Key 的保护是最后一道防线。

---

## 部署拓扑

### 开发 / 单机

```text
+------------------------------------------+
|  单进程                                   |
|  keycerthub + SQLite + dev-file Seal     |
+------------------------------------------+
```

### 生产高可用（阶段 6）

```text
              +-----------------+
              | Load Balancer   |
              +--------+--------+
                       |
        +--------------+--------------+
        |                             |
+-------v-------+             +-------v-------+
| Active Node   |  <------->  | Standby Node  |
| keycerthub    |  心跳/转发   | keycerthub    |
+-------+-------+             +-------+-------+
        |                             |
        +--------------+--------------+
                       |
              +--------v---------+
              | PostgreSQL 主备   |
              | Streaming Repl.  |
              +------------------+
```

### Provider 进程隔离（阶段 5）

```text
+---------------------------+
|  keycerthub (OpenSSL)     |
+-------------+-------------+
              | Unix Socket / gRPC + mTLS
     +--------+--------+
     |                 |
+----v-----------+ +---v---------------+
| gmssl-provider | | pkcs11-provider   |
| (链接 GmSSL)   | | (链接 PKCS#11)    |
+----------------+ +-------------------+
```

**为什么必须进程隔离**：OpenSSL 与 GmSSL 可能导出同名符号、头文件定义冲突、
SM2 默认参数行为不一致、内存分配器互相干扰。进程隔离同时带来崩溃隔离，
并与「真实密码机本来就在进程外」的形态一致，便于后续平滑替换为硬件设备。

---

## 架构决策记录（ADR）

重大决策记录在 [`adr/`](adr/README.md) 目录：

| 编号 | 决策 | 状态 |
|---|---|---|
| ADR-0001 | 选择 C++17 作为实现语言 | 已接受 |
| ADR-0002 | GmSSL 采用进程隔离而非同进程链接 | 已接受 |
| ADR-0003 | 复用 PostgreSQL 而非自研分布式共识 | 已接受 |
| ADR-0004 | 不自研密码算法与协议格式 | 已接受 |
| ADR-0005 | 以 Linux 为唯一一等目标平台 | 已接受 |
| ADR-0006 | 首版接口用 REST 而非 gRPC | 已接受 |

---

## 待补充

- [ ] 阶段 4：多租户下的完整部署拓扑
- [ ] 阶段 5：Provider 进程通信协议细节（帧格式、超时、重连）
- [ ] 阶段 6：主备切换时序图与脑裂防护细节
- [ ] 阶段 6：缓存失效传播机制图
