# 贡献指南

## 分支模型

- `main`：始终可构建、测试通过
- `feat/<scope>`：新功能
- `fix/<scope>`：缺陷修复
- `docs/<scope>`：文档

## 提交信息

遵循约定式提交：

```
<type>(<scope>): <subject>

type: feat | fix | docs | test | refactor | perf | build | ci | chore
scope: key | cert | crypto | provider | policy | audit | api | db | deploy
```

示例：

```
feat(key): 实现密钥版本轮换与 min_decrypt_version 校验
fix(provider): 修正 SM2 用户 ID 未参与 ZA 计算的问题
```

## 代码规范

- 遵循 `.clang-format`，提交前执行 `clang-format -i`
- 通过 `.clang-tidy` 检查
- 禁用规则见总体设计文档 20.6

## 提交前检查清单

- [ ] `cmake --build --preset debug` 通过
- [ ] `ctest --preset debug` 全部通过
- [ ] ASan/UBSan 构建无错误
- [ ] 新增代码有对应测试
- [ ] 未提交任何密钥、Token、密码
- [ ] 文档与代码保持同步

## 安全相关

- 密码相关改动必须附带测试向量或交叉验证结果
- 不得自行设计密码算法、模式或格式（应使用标准）
- 发现安全问题请走 `SECURITY.md` 流程，不要直接开 Issue
