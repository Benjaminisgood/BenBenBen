# BenBenBen Shell Runtime

`Runtime/Benshell` 是 BenBenBen 2.x 的当前 shell 环境。它由 Runtime 安装器原子发布，并通过 `BENSHELL_HOME` 加载。

## 当前入口

```bash
benbenben status
benbenben build
benbenben test
benbenben verify
bbb runtime status --json
```

`benbenben` 是完整 CLI，`bbb` 是短别名。

## 目录

```text
Benshell/
├── scripts/          固定项目控制器
├── zsh/              exports、functions、aliases
├── bootstrap/        显式环境安装脚本
└── Brewfile          可选依赖清单
```

Runtime 启动不会自动运行 Brewfile、macOS defaults、Git 同步或服务启动。

## 环境变量

- `BENBENBEN_RUNTIME_HOME`：当前 Runtime 根目录。
- `BENSHELL_HOME`：当前 shell 层目录。
- `BENBENBEN_PROJECT_HOME`：BenBenBen 仓库。
- `BENBENBEN_APP_NAME`：App 进程名。
- `BENBENBEN_GIT_REMOTE`：显式 Git 操作使用的 remote。

## 验证

```bash
./Scripts/test-runtime.sh
```
