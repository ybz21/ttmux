#!/usr/bin/env bash
#
# 验证 agent e2e 测试结果
# 用法: bash tests/verify_agent_e2e.sh
#

set -euo pipefail

DIR="/tmp/ttmux-agent-test"
PASS=0
FAIL=0

bold=$'\033[1m'
green=$'\033[32m'
red=$'\033[31m'
dim=$'\033[2m'
reset=$'\033[0m'

pass() { echo -e "  ${green}✔${reset} $1"; ((PASS++)) || true; }
fail() { echo -e "  ${red}✘${reset} $1"; ((FAIL++)) || true; }

echo ""
echo -e "${bold}Agent E2E 验证${reset}"
echo -e "${dim}$(printf '─%.0s' {1..40})${reset}"
echo ""

# 文件存在性
echo -e "${bold}[文件检查]${reset}"
for f in string_utils.py math_utils.py file_utils.py main.py; do
    [[ -f "${DIR}/${f}" ]] && pass "${f} 存在" || fail "${f} 缺失"
done
echo ""

# 函数存在性
echo -e "${bold}[函数检查]${reset}"
for func in reverse count_vowels to_snake_case; do
    grep -q "def ${func}" "${DIR}/string_utils.py" 2>/dev/null \
        && pass "string_utils.${func}" || fail "string_utils.${func} 缺失"
done
for func in is_prime fibonacci gcd; do
    grep -q "def ${func}" "${DIR}/math_utils.py" 2>/dev/null \
        && pass "math_utils.${func}" || fail "math_utils.${func} 缺失"
done
for func in read_lines word_count find_files; do
    grep -q "def ${func}" "${DIR}/file_utils.py" 2>/dev/null \
        && pass "file_utils.${func}" || fail "file_utils.${func} 缺失"
done
echo ""

# 功能测试
echo -e "${bold}[功能验证]${reset}"

# string_utils
result=$(cd "$DIR" && python3 -c "from string_utils import reverse; print(reverse('hello'))" 2>&1) || true
[[ "$result" == "olleh" ]] && pass "reverse('hello') = olleh" || fail "reverse: got '${result}'"

result=$(cd "$DIR" && python3 -c "from string_utils import count_vowels; print(count_vowels('hello'))" 2>&1) || true
[[ "$result" == "2" ]] && pass "count_vowels('hello') = 2" || fail "count_vowels: got '${result}'"

result=$(cd "$DIR" && python3 -c "from string_utils import to_snake_case; print(to_snake_case('helloWorld'))" 2>&1) || true
[[ "$result" == "hello_world" ]] && pass "to_snake_case('helloWorld') = hello_world" || fail "to_snake_case: got '${result}'"

# math_utils
result=$(cd "$DIR" && python3 -c "from math_utils import is_prime; print(is_prime(7))" 2>&1) || true
[[ "$result" == "True" ]] && pass "is_prime(7) = True" || fail "is_prime: got '${result}'"

result=$(cd "$DIR" && python3 -c "from math_utils import fibonacci; print(fibonacci(10))" 2>&1) || true
[[ "$result" == "55" ]] && pass "fibonacci(10) = 55" || fail "fibonacci: got '${result}'"

result=$(cd "$DIR" && python3 -c "from math_utils import gcd; print(gcd(12, 8))" 2>&1) || true
[[ "$result" == "4" ]] && pass "gcd(12, 8) = 4" || fail "gcd: got '${result}'"

# file_utils
echo "hello world" > "${DIR}/test_file.txt"
result=$(cd "$DIR" && python3 -c "from file_utils import read_lines; print(len(read_lines('test_file.txt')))" 2>&1) || true
[[ "$result" == "1" ]] && pass "read_lines 返回 1 行" || fail "read_lines: got '${result}'"

result=$(cd "$DIR" && python3 -c "from file_utils import word_count; print(word_count('test_file.txt'))" 2>&1) || true
[[ "$result" == "2" ]] && pass "word_count = 2" || fail "word_count: got '${result}'"
rm -f "${DIR}/test_file.txt"

# main.py 可运行
result=$(cd "$DIR" && python3 main.py 2>&1; echo "EXIT:$?")
echo "$result" | grep -q "EXIT:0" && pass "main.py 运行成功" || fail "main.py 运行失败"

echo ""
echo -e "${dim}$(printf '─%.0s' {1..40})${reset}"
total=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
    echo -e "${green}${bold}全部通过${reset} ${dim}(${total}/${total})${reset}"
else
    echo -e "${red}${bold}${FAIL} 个失败${reset} ${dim}(${PASS}/${total} 通过)${reset}"
fi
echo ""

exit $FAIL
