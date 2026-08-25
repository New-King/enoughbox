# Contributing to EnoughBox

[中文插件发布政策 → docs/插件发布.md](docs/插件发布.md)

## 宿主（EnoughBox App）

1. 重大 scope 变更先开 Issue 讨论  
2. UI 遵循 [docs/设计规范.md](docs/设计规范.md)  
3. 文案只用 String Catalog key，见 [docs/MVP.md](docs/MVP.md) §10  
4. 不提交密钥、`.plugin` 二进制（CI 构建除外）

## 官方插件（plugin-registry）

**官方插件中心为审核制，不支持随意上传。**

1. 阅读 [docs/插件发布.md](docs/插件发布.md)  
2. 开发插件（参考 `Plugins/SamplePlugin/`，工程就绪后）  
3. 提 PR：源码 + `plugin-registry/manifest.json` 条目  
4. 等待审核与 CI 构建；合并后用户方可从插件中心安装  

## Fork 自建商店

可 fork 后修改默认 manifest URL、自行审核与签名；无需合并回本仓库。
