# 密钥管理设计

> **状态**：✅ 已成稿
> **设计依据**：`00-总体设计与实施路线图.md` 第六、七章
> **实现阶段**：阶段 2

---

## 密钥模型与用途

### 逻辑密钥与版本

```text
Managed Key（逻辑密钥）
  ├── key_id            逻辑标识，租户内唯一
  ├── tenant_id         所属租户
  ├── algorithm         算法（创建后不可变）
  ├── purposes           用途位标志（可扩展，不可越权）
  ├── status             当前整体状态
  ├── latest_version    最新版本号
  ├── min_encrypt_version 允许用于加密的最小版本
  ├── min_decrypt_version 允许用于解密的最小版本
  └── versions[]         各版本 KeyVersion
```

### 密钥类型

```cpp
enum class KeyAlgorithm {
    AES_128_GCM, AES_256_GCM,
    SM4_GCM, SM4_CBC,
    RSA_2048, RSA_3072, RSA_4096,
    ECDSA_P256, ECDSA_P384, ECDSA_P521,
    ED25519,
    SM2,
    HMAC_SHA256, HMAC_SM3,
    ML_KEM_768, ML_DSA_65      // 阶段 8
};
```

### 密钥用途

```cpp
enum class KeyPurpose : std::uint32_t {
    None             = 0,
    Encrypt          = 1U << 0,
    Decrypt          = 1U << 1,
    Sign             = 1U << 2,
    Verify           = 1U << 3,
    Wrap             = 1U << 4,
    Unwrap           = 1U << 5,
    IssueCertificate = 1U << 6,
    Derive           = 1U << 7,
    Mac              = 1U << 8
};
```

### 用途隔离规则

| 规则 | 说明 |
|---|---|
| 签名密钥不得用于普通加密 | 防止密钥用途混用导致的密码学风险 |
| CA 私钥仅限 `IssueCertificate` | 不得用于数据加密或普通签名 |
| KEK 仅限 `Wrap` / `Unwrap` | 不得直接加密业务数据 |
| DEK 仅限 `Encrypt` / `Decrypt` | 不得用于签名 |
| 验签只需公钥 | 禁止无意义地加载私钥 |
| 用途不匹配一律拒绝 | **不允许自动降级或隐式放宽** |

**每次调用都必须校验用途**，不能只在创建时检查。

---

## 状态机与合法转换

```text
                 创建
                  |
                  v
            +-----------+
            |  CREATED  |
            +-----+-----+
                  | activate
                  v
            +-----------+  suspend   +-------------+
            |  ACTIVE   | ---------> |  SUSPENDED  |
            +-----+-----+ <--------- +-------------+
                  |        resume
      +-----------+-----------+
      |                       |
  rotate                   revoke
      v                       v
 +-----------+          +-----------+
 |  RETIRED  |          |  REVOKED  |
 +-----+-----+          +-----+-----+
       |                      |
       +----------+-----------+
                  | destroy
                  v
            +-------------+
            |  DESTROYED  |
            +-------------+
```

### 合法转换表

| 起始状态 | 允许转换到 | 触发操作 |
|---|---|---|
| CREATED | ACTIVE、REVOKED、DESTROYED | activate / revoke / destroy |
| ACTIVE | SUSPENDED、RETIRED、REVOKED | suspend / rotate / revoke |
| SUSPENDED | ACTIVE、REVOKED、DESTROYED | resume / revoke / destroy |
| RETIRED | ACTIVE（回滚）、REVOKED、DESTROYED | activate / revoke / destroy |
| REVOKED | DESTROYED | destroy |
| DESTROYED | —（终态） | — |

**非法转换必须抛出明确错误**，不得静默忽略。所有转换写入审计。

### 状态能力矩阵

| 状态 | 新加密 | 解密历史 | 签名 | 验签 | 轮换 | 导出 |
|---|---:|---:|---:|---:|---:|---:|
| CREATED | 否 | 否 | 否 | 是 | 否 | 否 |
| ACTIVE | 是 | 是 | 是 | 是 | 是 | 按策略 |
| SUSPENDED | 否 | 否 | 否 | 是 | 否 | 否 |
| RETIRED | 否 | 是 | 否 | 是 | 否 | 按策略 |
| REVOKED | 否 | 默认否 | 否 | 是 | 否 | 否 |
| DESTROYED | 否 | 否 | 否 | 仅公钥 | 否 | 否 |

> `REVOKED` 的「解密历史」默认为否。若业务需要（如密钥泄露但历史数据仍需可读），
> 需通过显式配置放宽，并强制记录审计与告警。

---

## 版本管理

```text
Key: payment-data (tenant: acme)
  latest_version      = 3
  min_encrypt_version = 3
  min_decrypt_version = 1

KeyVersion 1  RETIRED   可解密历史数据
KeyVersion 2  RETIRED   可解密历史数据
KeyVersion 3  ACTIVE    当前加密与签名使用
```

### 规则

1. 新加密/签名默认使用最新 `ACTIVE` 版本
2. 密文与签名**必须**携带 `key_id` + `key_version`（写入 Envelope，见 `crypto-design.md`）
3. 旧版本保留 `DECRYPT` / `VERIFY` 能力
4. 版本低于 `min_decrypt_version` 时拒绝解密，返回 `KEY_VERSION_TOO_OLD`
5. `min_encrypt_version` 用于强制新数据使用新密钥
6. 轮换必须在数据库事务内完成
7. 同一逻辑密钥**最多一个 `ACTIVE` 版本**（数据库唯一约束 + 应用层 CAS 双重保证）
8. 销毁清除密钥材料，保留元数据与审计记录

---

## 轮换语义

```text
轮换前：
  v1 ACTIVE   ← 加密使用
  v2 RETIRED

执行 rotate：
  1. 生成新密钥材料 v3
  2. 使用 Master Key 加密 v3 材料
  3. 事务内：v1 -> RETIRED，v3 -> ACTIVE
  4. latest_version = 3
  5. min_encrypt_version = 3（可选，强制切换）
  6. 写审计 + 指标

轮换后：
  v1 RETIRED  ← 仍可解密历史密文
  v2 RETIRED
  v3 ACTIVE   ← 新加密使用
```

### 并发安全

```text
方式一：数据库唯一部分索引
  CREATE UNIQUE INDEX ... ON key_versions(tenant_id, key_id)
  WHERE status = 'ACTIVE';

方式二：版本 CAS
  UPDATE managed_keys
     SET latest_version = :new, updated_at = now()
   WHERE tenant_id = :t AND key_id = :k
     AND latest_version = :expected;
  -- 影响行数为 0 则说明并发冲突，重试或返回 CONFLICT

生产建议：两者同时使用
```

**旧数据不会失效**，这是密钥管理系统的核心设计目标。

---

## 自动轮换策略

```cpp
struct RotationPolicy {
    std::optional<std::chrono::days> interval;      // 时间触发
    std::optional<std::uint64_t>     max_operations; // 操作次数触发
    std::optional<std::uint64_t>     max_encryptions;// GCM 安全上限触发
    bool rotate_on_compromise = false;              // 事件触发（阶段 3+）
};
```

### 触发条件

```text
三者中先满足者触发：
  now >= next_rotation_at                        （时间）
  usage_count      >= max_operations             （次数）
  encryptions_count >= max_encryptions           （加密数）

默认 max_encryptions = 2^31
  依据：NIST SP 800-38D 建议 AES-GCM 单密钥加密不超过 2^32，
        取一半作为安全裕度，同时避免计数溢出
```

### 调度

```text
后台任务：scan_interval 默认 5 分钟
  1. 查询 next_rotation_at <= now 或计数超限的密钥
  2. 逐把执行 rotate（事务，失败隔离，不影响其他密钥）
  3. 更新 next_rotation_at = now + interval
  4. 上报指标 key_rotations_total、key_rotation_failures_total
  5. 失败重试上限 3 次，仍失败则告警
```

### 计数持久化

```text
usage_count / encryptions_count 存储于 key_versions 表
每次加密在事务内递增（与业务操作同事务，保证不丢失）
重启后计数不归零，避免累计超限
```

---

## 四层密钥保护

```text
Level 0  Seal Key
  来源：dev-file / mock-hsm / password(Argon2id) / shamir / kms
  作用：解封 Master Key
    |
    v
Level 1  Master Key (Root KEK)
  存储：加密后落库
  作用：加密所有 Managed Key 材料
    |
    v
Level 2  Managed Keys (KEK / DEK / 签名密钥 / CA 私钥)
  存储：元数据明文 + 材料密文
  作用：业务加解密、签名、包装 DEK
    |
    v
Level 3  Per-request DEK
  存储：随业务密文保存 Wrapped 形式
  作用：加密实际业务数据
```

### 为什么必须分层

| 密钥 | 生命周期 | 使用频率 | 权限 | 混用的后果 |
|---|---|---|---|---|
| Master Key | 年级 | 极低 | 最高 | 暴露面扩大且无法轮换 |
| Managed Key | 月～年级 | 高 | 中 | — |
| DEK | 单次 | 一次 | 低 | — |

**Master Key 绝不直接用于业务数据加密**，只用于保护其他密钥材料。

### Seal 状态机

```text
    启动
     |
     v
 +---------+  unseal(正确 Seal Key)  +-----------+
 | SEALED  | ----------------------> | UNSEALED  |
 +---------+                         +-----------+
     ^                                     |
     |      seal() / 重启 / 存储致命错误     |
     +-------------------------------------+
```

| 状态 | 允许 | 禁止 |
|---|---|---|
| SEALED | `/health`、`/seal/status`、`/seal/unseal`、`/version` | 读取材料、加解密、签名、签发、轮换、销毁 |
| UNSEALED | 全部（受权限与策略约束） | — |

### Master Key 轮换

```text
1. 生成 Master Key v2，用 Seal Key 加密并落库
2. 开启双写窗口：新写入使用 v2
3. 后台任务逐条重加密存量材料（v1 -> v2），记录进度游标
4. 全部完成后标记 v1 为 retired
5. 记录轮换审计与进度指标（master_key_reencrypt_progress）
```

**要求**：可中断、可续跑（进度游标持久化）；轮换期间两版本均可解密。

---

## 密钥材料落库格式

```json
{
  "format_version": 1,
  "wrapping_algorithm": "AES-256-GCM",
  "master_key_version": 1,
  "nonce": "base64...",
  "ciphertext": "base64...",
  "tag": "base64..."
}
```

### 材料编码规范

| 密钥类型 | 私钥/材料格式 | 公钥格式 |
|---|---|---|
| AES / SM4 / HMAC | 原始字节（Raw） | — |
| RSA / ECDSA / Ed25519 / SM2 | PKCS#8 DER | SubjectPublicKeyInfo (SPKI) DER |

统一使用 DER 而非 PEM，避免解析歧义与额外开销；导出时再转 PEM。

---

## AAD 绑定

```text
AAD = tenant_id ‖ 0x00 ‖ key_id ‖ 0x00 ‖ key_version(4B BE)
      ‖ 0x00 ‖ algorithm ‖ 0x00 ‖ purposes(4B BE)
```

### 为什么必须绑定

| 攻击场景 | 无 AAD 的后果 | 有 AAD 的结果 |
|---|---|---|
| 把密钥 A 的材料密文搬到密钥 B | B 使用 A 的密钥材料，策略被绕过 | GCM 认证失败 |
| 把 v1 材料搬到 v3 | 版本语义被破坏 | 认证失败 |
| 跨租户搬移材料 | 租户隔离失效 | 认证失败 |

**验证方式**：在数据库中交换两条 `encrypted_material` 后，解密必须失败。
这是阶段 2 的必测项。

---

## 导入与导出（BYOK）

### 导入

```text
POST /api/v1/{tenant}/keys/import

校验：
  1. 算法与声明一致（解析实际格式，不信任声明）
  2. 用途合法
  3. 格式可解析（PKCS#8 / SPKI / Raw）
  4. 密钥长度符合算法要求
  5. 若为私钥，校验与公钥是否匹配（如提供）
导入后：
  立即用 Master Key 加密材料后落库
  明文材料在内存中尽快清理
  记录审计：导入来源、算法、操作人
```

### 导出

```text
POST /api/v1/{tenant}/keys/{keyId}/export

前置条件（全部满足才允许）：
  1. 密钥 exportable = true
  2. 调用方角色为 KEY_ADMIN 或更高
  3. 策略允许该 Actor 导出该密钥
  4. 租户配额允许
  5. 记录审计（导出是高危操作）

默认行为：exportable = false，公钥导出不受限
```

### 备份与恢复

```text
备份包结构：
  header（格式版本、算法、KDF 参数）
  + 加密的密钥材料集合
  + 元数据（key_id、versions、purposes）
  + HMAC 校验值

加密：独立口令派生密钥（Argon2id）或 KEK 包装
要求：
  备份包必须加密（备份存储视为不可信）
  backup_records 表只记录元数据与校验值，不保存备份内容
  恢复时校验 HMAC，检测篡改
  恢复遇到版本冲突时拒绝并报告，不静默覆盖
```

---

## 使用计数与配额

| 字段 | 位置 | 用途 |
|---|---|---|
| `usage_count` | `key_versions` | 该版本总操作次数 |
| `encryptions_count` | `key_versions` | 该版本加密次数（GCM 安全上限依据） |
| `last_used_at` | `key_versions` | 识别僵尸密钥，辅助清理 |

**更新时机**：与业务操作同一事务，保证不丢失。

**配额维度**：租户级密钥总数、单密钥操作 QPS、单次请求大小、批量项数。

---

## 销毁语义

```text
POST /api/v1/{tenant}/keys/{keyId}/destroy

行为：
  1. 校验状态允许销毁（不能销毁 CREATED 以外的 ACTIVE 密钥，除非先 revoke）
  2. 清除 encrypted_material（置 NULL 或覆写）
  3. 清除 provider_key_ref（若为 HSM，调用设备删除接口）
  4. 状态置 DESTROYED，记录 destroyed_at
  5. 保留元数据与审计记录
  6. 高危操作，建议要求双人授权（阶段 8）

不可逆：销毁后无法恢复解密能力
必须明确告知调用方：历史密文将永久无法解密
```

---

## 待补充

- [ ] 阶段 2：补充密钥属性模板（KM-17）的预定义组合
- [ ] 阶段 5：补充密钥托管与恢复代理（KM-18）流程
- [ ] 阶段 5：补充密钥仪式记录（KM-19）模板
- [ ] 阶段 8：补充跨区域密钥复制（KM-21）一致性设计
