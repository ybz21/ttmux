# 测试任务：构建 minitools Python 工具包

## 目标

在 /tmp/ttmux-agent-test 目录下创建一个 Python 工具包 `minitools`，由 3 个独立模块组成。

## 要求

使用 `ttmux agent spawn` 将任务拆分为 3 个并行子 Claude 执行：

### 子任务 1: string_utils
- 文件: `/tmp/ttmux-agent-test/string_utils.py`
- 内容: 实现 3 个函数
  - `reverse(s)` — 反转字符串
  - `count_vowels(s)` — 统计元音字母数量
  - `to_snake_case(s)` — 驼峰转蛇形

### 子任务 2: math_utils
- 文件: `/tmp/ttmux-agent-test/math_utils.py`
- 内容: 实现 3 个函数
  - `is_prime(n)` — 判断素数
  - `fibonacci(n)` — 返回第 n 个斐波那契数
  - `gcd(a, b)` — 最大公约数

### 子任务 3: file_utils
- 文件: `/tmp/ttmux-agent-test/file_utils.py`
- 内容: 实现 3 个函数
  - `read_lines(path)` — 读取文件返回行列表
  - `word_count(path)` — 统计文件单词数
  - `find_files(directory, pattern)` — 按 glob 模式查找文件

## 组装

3 个子任务完成后：
1. 收集所有 agent 输出确认完成
2. 创建 `/tmp/ttmux-agent-test/main.py`，import 三个模块并各调用一个函数做演示
3. 运行 `python3 /tmp/ttmux-agent-test/main.py` 验证
4. 清理 agent 组

## 执行命令参考

```bash
ttmux agent spawn minitools \
  "string" "在 /tmp/ttmux-agent-test/string_utils.py 中实现 reverse, count_vowels, to_snake_case 三个函数" \
  "math"   "在 /tmp/ttmux-agent-test/math_utils.py 中实现 is_prime, fibonacci, gcd 三个函数" \
  "file"   "在 /tmp/ttmux-agent-test/file_utils.py 中实现 read_lines, word_count, find_files 三个函数" \
  --dir /tmp/ttmux-agent-test --perm auto
```
