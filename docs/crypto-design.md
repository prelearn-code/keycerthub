# 密码设计

> **状态**：✅ 已成稿
> **设计依据**：`00-总体设计与实施路线图.md` 第八、九章
> **实现阶段**：阶段 1

---

## 设计原则

1. **不自研算法**：一律调用 OpenSSL/GmSSL，工程的难点在参数、格式、密钥体系与治理
2. **参数显式**：不依赖任何库的默认值，全部显式设置并记录
3. **格式自描述**：算法、版本、编码写入密文/签名，不靠约定猜测
4. **失败关闭**：认证失败、参数不匹配、能力缺失一律拒绝
5. **错误不区分**：解密类失败统一错误码，避免构造解密 Oracle

---

## 算法清单与禁用清单

| 用途 | 允许 | 禁止 | 版本 |
|---|---|---|---|
| 对称加密 | AES-256-GCM、SM4-GCM、SM4-CBC+HMAC-SM3 | DES、3DES、RC4、AES-ECB、**裸 CBC** | V1 |
| 非对称加密 | RSA-OAEP(SHA-256)、SM2 | 裸 RSA、PKCS#1 v1.5 加密 | V1 |
| 签名 | RSA-PSS、ECDSA、Ed25519、SM2 | MD5/SHA-1 签名、PKCS#1 v1.5 新用途 | V1 |
| 密钥交换 | ECDHE、SM2 密钥交换 | 静态 RSA 密钥传输 | V1 |
| 摘要 | SHA-256/384/512、SM3 | MD5、SHA-1 | V1 |
| MAC | HMAC-SHA256、HMAC-SM3 | 裸 Hash 作 MAC、自创 MAC 构造 | V1 |
| 密钥包装 | AES-256-KWP | 自创包装格式 | V1 |
| 口令存储 | Argon2id、scrypt、bcrypt | 单轮 Hash、明文、可逆加密 | V1 |
| 随机数 | CSPRNG（`RAND_bytes` / `OSSL_RAND`） | 时间戳、计数器、`rand()` | V1 |
| PQC | ML-KEM-768、ML-DSA-65（混合模式） | 单独使用 PQC 而不做混合 | V3 |

> 完整禁用清单与合规对照见 [`compliance.md`](compliance.md)。

---

## AES-256-GCM 参数

```text
算法      AES-256-GCM
密钥长度   32 字节
Nonce     12 字节（96 bit），CSPRNG 生成
Tag       16 字节（128 bit）
AAD       可选；解密时必须与加密时逐字节一致
```

### 硬性规则

| 规则 | 原因 |
|---|---|
| Nonce 必须 CSPRNG 生成 | 可预测 Nonce 会导致密钥流复用 |
| 同一密钥下严禁 Nonce 重复 | GCM 在 Nonce 复用下可导致认证密钥恢复 |
| 解密必须先验 Tag 再返回明文 | 避免 Padding/Oracle 类攻击 |
| Tag 失败统一 `CRYPTO_AUTH_FAILED` | 不区分「密钥错」「密文坏」「Tag 错」 |
| 完整 AAD 不入审计日志 | 只记 `aad_hash`，防敏感信息泄漏 |
| 单密钥加密次数受监控 | NIST SP 800-38D：接近 2³² 前必须轮换 |
| 加密计数持久化 | 重启后计数不丢失，避免累计超限 |

### 加密次数上限处理

```text
默认阈值 max_encryptions = 2^31（安全上限的一半，留缓冲）

触发链：
  usage_count 递增（每次加密，事务内）
    -> 达到 rotation_max_operations 或 max_encryptions
    -> 后台轮换任务生成新版本并激活
    -> 旧版本转 RETIRED，仅保留解密能力
    -> 指标 key_rotations_total++ 并告警
```

### 代码要点

```cpp
// 正确：显式设置全部参数
EVP_EncryptInit_ex2(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr);
EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, nullptr);
EVP_EncryptInit_ex2(ctx, nullptr, nullptr, key.data(), nonce.data());
EVP_EncryptUpdate(ctx, nullptr, &outlen, aad.data(), aad.size());   // AAD
EVP_EncryptUpdate(ctx, out, &outlen, plaintext.data(), plaintext.size());
EVP_EncryptFinal_ex(ctx, out + outlen, &tmplen);
EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
```

---

## SM4 参数与 Encrypt-then-MAC

不同版本的 OpenSSL/GmSSL 对 SM4 模式支持不一致，因此采用**能力协商**：

```text
首选：SM4-GCM（Provider 支持时）
基线：SM4-CBC + HMAC-SM3（Encrypt-then-MAC）
```

### SM4-GCM

```text
密钥 16 字节 | Nonce 12 字节 | Tag 16 字节
约束与 AES-GCM 完全一致
```

### SM4-CBC + HMAC-SM3（基线方案）

```text
加密密钥 16 字节（独立生成）
MAC 密钥 16 字节（独立生成，绝不复用加密密钥）
IV       16 字节（CSPRNG）
PKCS#7 填充
```

**MAC 计算范围**：

```text
MAC = HMAC-SM3(mac_key,
               format_version ‖ algorithm ‖ iv ‖ aad ‖ ciphertext)
```

**硬性规则**：

1. 禁止裸 SM4-CBC（无完整性保护）
2. 加密密钥与 MAC 密钥必须独立生成
3. 先验 MAC，再解密（Encrypt-then-MAC）
4. MAC 比较使用恒定时间函数（`CRYPTO_memcmp`）
5. Padding 错误与 MAC 错误对外返回**同一**错误码
6. 密文格式中必须记录实际使用的是 GCM 还是 CBC+HMAC 变体

> 选择 Encrypt-then-MAC 而非 MAC-then-Encrypt：前者可先拒绝伪造密文，
> 不给解密逻辑处理攻击者数据的机会。

---

## RSA-OAEP / RSA-PSS 参数

```text
加解密     RSA-OAEP
摘要       SHA-256
MGF        MGF1-SHA256
Label      nullptr（不使用 label）
最小密钥   2048 bit（推荐 3072）

签名验签   RSA-PSS
摘要       SHA-256
MGF        MGF1-SHA256
Salt 长度  = 摘要长度（32 字节）
最小密钥   2048 bit
```

### 硬性规则

| 规则 | 说明 |
|---|---|
| MGF 必须显式设置 | 默认 MGF1 与摘要一致，但跨库不保证 |
| Salt 长度必须显式设置 | 默认值在不同库/版本可能不同 |
| 超长明文必须拒绝并给出明确错误 | RSA 明文长度上限 = key_size - 2*hash_len - 2 |
| 签名验证失败统一 `SIGNATURE_INVALID` | 不暴露具体失败原因 |
| 禁止用 RSA 直接加密大文件 | 应使用信封加密（KEK 包装 DEK） |

### 代码要点

```cpp
// 签名：显式设置 PSS 与 Salt 长度
EVP_PKEY_CTX_set_rsa_padding(pctx, RSA_PKCS1_PSS_PADDING);
EVP_PKEY_CTX_set_rsa_pss_saltlen(pctx, RSA_PSS_SALTLEN_DIGEST);
EVP_PKEY_CTX_set_rsa_mgf1_md(pctx, EVP_sha256());

// 加密：显式设置 OAEP 与 MGF1
EVP_PKEY_CTX_set_rsa_padding(pctx, RSA_PKCS1_OAEP_PADDING);
EVP_PKEY_CTX_set_rsa_oaep_md(pctx, EVP_sha256());
EVP_PKEY_CTX_set_rsa_mgf1_md(pctx, EVP_sha256());
```

---

## ECDSA 与 Ed25519

```text
ECDSA
  曲线    P-256（默认）/ P-384 / P-521
  摘要    SHA-256 / SHA-384 / SHA-512
  编码    ASN.1 DER（默认），可选 Raw r‖s
  随机数  每次签名必须使用 CSPRNG（k 值可预测则私钥可恢复）

Ed25519
  摘要    无独立参数（EdDSA 内部处理）
  编码    固定 64 字节
  特点    确定性签名，无 k 值风险
```

**ECDSA 签名编码注意**：DER 编码长度可变，Raw 编码固定；两者必须显式标注，
否则跨库验签会失败。系统在签名结果中通过 `encoding` 字段声明。

---

## SM2 用户 ID 与 ZA

SM2 签名必须显式处理用户标识，这是**跨库验签失败的首要原因**。

```text
ZA = SM3(ENTL ‖ ID ‖ a ‖ b ‖ xG ‖ yG ‖ xA ‖ yA)
e  = SM3(ZA ‖ M)
签名 = SM2_Sign(e, d)

ENTL = ID 的比特长度的 2 字节大端表示
ID   = 用户标识，默认 "1234567812345678"（16 字节 ASCII）
```

### 硬性规则

1. **摘要必须是 SM3**，不得使用 SHA-256
2. **User ID 必须显式传递并记录**，不得依赖库默认值
3. **签名格式必须标注**（ASN.1 DER 或 Raw `r‖s`）
4. **公钥点编码必须明确**（压缩/非压缩）
5. **是否预哈希必须明确**（对 e 签名 还是 对 M 签名）

### 跨库验签失败四大原因

| 原因 | 现象 | 排查方式 |
|---|---|---|
| User ID 不一致 | 一方验签必失败 | 核对双方配置的 ID |
| 签名编码不同 | DER 被当作 Raw 解析 | 查看签名长度是否 64 字节 |
| 公钥点编码不同 | 公钥解析失败或点无效 | 查看首字节 0x02/0x03/0x04 |
| 预哈希不一致 | 签名值语义不同 | 确认对 e 还是对 M 签名 |

### 使用约束

```text
SM2 加密仅用于短数据（≤ 明文上限）或密钥材料包装
不得用于大文件加密（应使用 SM2 包装 DEK，再由 DEK 加密数据）
```

---

## 抗量子算法（阶段 8）

```text
ML-KEM-768（原 Kyber）   密钥封装
ML-DSA-65（原 Dilithium）签名

混合模式（强制）：
  密钥交换：ECDHE + ML-KEM 同时执行，两者都成功才接受
  签名：经典签名 + PQC 签名双签，验证时要求两者都通过
  证书：混合证书（SubjectPublicKeyInfo 中并存两套公钥）

实现来源：liboqs 或 OpenSSL 3.5+ 内建 PQC
```

**为什么强制混合**：PQC 算法较新，单独使用存在实现风险与兼容性问题；
混合模式保证即使一方被攻破，整体仍然安全，且过渡期可与现有系统互操作。

---

## 密文 Envelope 格式

### 业务密文

```json
{
  "format_version": 1,
  "algorithm": "AES-256-GCM",
  "key_id": "payment-data",
  "key_version": 3,
  "tenant_id": "acme",
  "nonce": "base64...",
  "ciphertext": "base64...",
  "tag": "base64...",
  "aad_hash": "sha256:hex..."
}
```

### 信封加密格式

```json
{
  "format_version": 1,
  "kek_id": "order-kek",
  "kek_version": 2,
  "tenant_id": "acme",
  "data_algorithm": "AES-256-GCM",
  "wrap_algorithm": "AES-256-KWP",
  "wrapped_dek": "base64...",
  "nonce": "base64...",
  "ciphertext": "base64...",
  "tag": "base64..."
}
```

### 格式设计四原则

| 原则 | 体现 |
|---|---|
| 自描述 | 算法、版本、编码全部显式记录 |
| 可演进 | `format_version` 支持格式升级 |
| 可校验 | `key_id`/`key_version`/`tenant_id` 参与 AAD |
| 不冗余 | 不保存可推导信息 |

### AAD 构造

```text
AAD = tenant_id ‖ 0x00 ‖ key_id ‖ 0x00 ‖ key_version(4B BE)
      ‖ 0x00 ‖ algorithm ‖ 0x00 ‖ purposes(4B BE)
```

**作用**：任何字段被篡改（把密文搬到其他 key、版本或租户下）都会导致认证失败。
分隔符使用 `0x00` 防止字段拼接歧义（如 `ab`+`c` 与 `a`+`bc`）。

---

## 流式格式

用于大文件分块加解密（CR-17）：

```text
+---------------------------------------------------+
| Header                                            |
|  magic(4B) | format_version(1B) | algorithm(1B)   |
|  key_id_len(2B) | key_id | key_version(4B)         |
|  chunk_size(4B) | base_nonce(8B)                  |
+---------------------------------------------------+
| Chunk 0: nonce = base_nonce ‖ counter(4B BE) = 0  |
|          ciphertext | tag(16B)                     |
| Chunk 1: nonce = base_nonce ‖ counter = 1         |
|          ...                                      |
+---------------------------------------------------+
| Trailer: chunk_count(8B) | final_tag(16B)          |
+---------------------------------------------------+
```

### 要求

| 要求 | 说明 |
|---|---|
| 每块独立 Nonce | `base_nonce ‖ counter`，counter 从 0 递增 |
| 块序号参与 AAD | 防块重排与块删除攻击 |
| 支持随机访问 | 给定块序号可直接定位解密 |
| 支持断点续传 | 解析 Header 后可跳过已处理块 |
| 低内存占用 | 单块内存，不加载整个文件 |
| 尾部完整性 | `final_tag` 覆盖块数，防截断攻击 |

---

## 签名格式

```json
{
  "format_version": 1,
  "algorithm": "SM2-SM3",
  "key_id": "contract-signing",
  "key_version": 2,
  "tenant_id": "acme",
  "encoding": "ASN1_DER",
  "signature": "base64...",
  "sm2_user_id": "base64..."
}
```

`encoding` 取值：`ASN1_DER` | `RAW_RS` | `FIXED`（Ed25519）。

---

## 随机数要求

| 用途 | 来源 | 长度 | 备注 |
|---|---|---|---|
| AES-GCM Nonce | `RAND_bytes` | 12 B | 每密钥下唯一 |
| SM4 IV | `RAND_bytes` | 16 B | 每次加密唯一 |
| RSA/ECDSA 密钥生成 | OpenSSL 内部 CSPRNG | — | 不得提供外部随机源 |
| SM2 k 值 | OpenSSL 内部 CSPRNG | — | 绝不可预测 |
| 序列号 | `RAND_bytes` | ≥ 8 B | 全局唯一，防碰撞 |
| Token | `RAND_bytes` | ≥ 16 B | ≥128 bit 熵 |
| DEK | `RAND_bytes` | 32 B | 每次加密独立生成 |

### 硬性规则

1. 禁止使用 `rand()`、`random()`、时间戳、进程 ID、计数器作为随机源
2. 随机数失败必须**报错终止**，不得降级继续
3. 启动时自检 CSPRNG 可用性
4. 支持 FIPS 模式时使用 FIPS 校验过的 DRBG（阶段 8）
5. 随机数质量检测符合 GM/T 0005（阶段 8）

---

## 待补充

- [ ] 阶段 1：补充各算法的完整测试向量来源与预期值
- [ ] 阶段 5：补充 SM2 与 GmSSL 的 User ID 实测对照表
- [ ] 阶段 8：补充 PQC 混合模式的证书结构设计
- [ ] 阶段 8：补充 FPE（FF1/FF3）参数与适用场景
