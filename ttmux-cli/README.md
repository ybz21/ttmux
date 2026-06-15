# ttmux-cli — ttmux 的模块化源码

根目录的 `ttmux` 是**单文件分发版**（install.sh / `curl | bash` 直接装这一个文件）。
但单文件太长不好维护，所以源码按模块拆在这里，用 `build.sh` 拼回单文件。

## 工作流

```bash
# 1. 改模块
vim ttmux-cli/lib/agent.sh

# 2. 重新生成根目录的 ttmux
bash ttmux-cli/build.sh

# 3. （可选）安装到 ~/.local/bin
bash install.sh
```

> ⚠ **不要手改根目录的 `ttmux`**——它是 `build.sh` 的生成物，下次 build 会被覆盖。
> 所有改动都在 `ttmux-cli/lib/*.sh` 里做。

## 模块（拼接顺序）

| 顺序 | 文件 | 内容 |
|------|------|------|
| 1 | `lib/00-header.sh` | shebang / 版本 / 目录变量 / `set -euo pipefail` |
| 2 | `lib/core.sh` | 颜色、图标、辅助函数、JSON 输出 |
| 3 | `lib/env.sh` | 全局环境变量 (`env set/rm/push` …) |
| 4 | `lib/group.sh` | 任务组管理 + 任务元数据（统一 cmd / agent） |
| 5 | `lib/status.sh` | `info` / `status` / 状态 JSON |
| 6 | `lib/spawn.sh` | `spawn` 批量创建并行任务 |
| 7 | `lib/capture.sh` | `capture` 捕获会话输出 |
| 8 | `lib/wait.sh` | `wait` 等待任务完成 |
| 9 | `lib/collect.sh` | `collect` 收集输出 |
| 10 | `lib/agent.sh` | 多 Claude Agent 编排 |
| 11 | `lib/completion.sh` | Tab 补全安装 |
| 12 | `lib/help.sh` | 帮助文本 |
| 13 | `lib/interactive.sh` | 交互模式（菜单 + 各交互子流程） |
| 14 | `lib/99-main.sh` | 主入口 / 命令分发 |

拼接顺序写死在 `build.sh` 的 `MODULES` 数组里（`00-header` 必须最前、`99-main` 必须最后）。
新增模块时在数组里插到合适位置即可。

## 为什么根 `ttmux` 仍在 git 里

`install.sh` 的 GitHub 路径会 `curl .../ttmux`，所以**生成物必须提交**，不能 gitignore。
即：每次改完模块、`build.sh` 重新生成后，连同 `ttmux` 一起提交。

## 校验

`build.sh` 末尾会自动 `bash -n` 语法自检。生成后可再跑一遍冒烟测试：

```bash
./ttmux help | head
./ttmux ls
```
