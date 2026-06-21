#!/usr/bin/env bash
#
# 验证 swarm 广场 @mention / listen 增量监听
# 用法: bash tests/test_swarm_listen.sh
#

set -euo pipefail

TTMUX="${TTMUX:-./ttmux}"
TMP="$(mktemp -d /tmp/ttmux-swarm-listen.XXXXXX)"
export TTMUX_HOME="${TMP}/home"
export TTMUX_DATA="${TMP}/data"

PASS=0
FAIL=0

bold=$'\033[1m'
green=$'\033[32m'
red=$'\033[31m'
dim=$'\033[2m'
reset=$'\033[0m'

pass() { echo -e "  ${green}✔${reset} $1"; ((PASS++)) || true; }
fail() { echo -e "  ${red}✘${reset} $1"; ((FAIL++)) || true; }

cleanup() {
    rm -rf "$TMP"
}
trap cleanup EXIT

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then
        pass "$label"
    else
        fail "$label"
        echo "---- output ----"
        echo "$haystack"
        echo "----------------"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then
        fail "$label"
        echo "---- output ----"
        echo "$haystack"
        echo "----------------"
    else
        pass "$label"
    fi
}

message_section() {
    sed '/状态摘要/,$d'
}

echo ""
echo -e "${bold}swarm listen / @mention 测试${reset}"
echo -e "${dim}$(printf '─%.0s' {1..44})${reset}"
echo ""

echo -e "${bold}[准备]${reset}"
"$TTMUX" swarm new listen-case --goal "监听 case" --no-master >/dev/null
pass "创建蜂群"

card=$("$TTMUX" swarm task add listen-case "前端返工" --assignee web 2>/dev/null)
[[ "$card" == "t1" ]] && pass "创建并派卡 t1 → web" || fail "创建卡片: got '${card}'"

"$TTMUX" swarm say listen-case --as human --to master --kind ask "补移动端验收" >/dev/null
"$TTMUX" swarm say listen-case --as master --to web --kind decide "#${card} 补空状态" >/dev/null
"$TTMUX" swarm say listen-case --as api --kind note "普通进度" >/dev/null
pass "写入 master/web/普通三类广场消息"
echo ""

echo -e "${bold}[@mention 写入]${reset}"
feed=$("$TTMUX" swarm feed listen-case)
assert_contains "$feed" "@master 补移动端验收" "--to master 自动写入 @master"
assert_contains "$feed" "@web #t1 补空状态" "--to web 自动写入 @web"
assert_contains "$feed" "普通进度" "普通消息仍保留"
echo ""

echo -e "${bold}[master listen]${reset}"
master_out=$("$TTMUX" swarm listen listen-case --as master --once --no-advance)
master_msgs=$(printf '%s\n' "$master_out" | message_section)
assert_contains "$master_msgs" "[HIGH]" "master 标注 human/@master 为 HIGH"
assert_contains "$master_msgs" "@master 补移动端验收" "master 看到 human 指令"
assert_contains "$master_msgs" "@web #t1 补空状态" "master 看到全量广场消息"
echo ""

echo -e "${bold}[worker mentions listen]${reset}"
web_out=$("$TTMUX" swarm listen listen-case --as web --mentions --once --no-advance)
web_msgs=$(printf '%s\n' "$web_out" | message_section)
assert_contains "$web_msgs" "@web #t1 补空状态" "web worker 收到 @web 消息"
assert_not_contains "$web_msgs" "@master 补移动端验收" "web worker 不收 @master 消息"
assert_not_contains "$web_msgs" "普通进度" "web worker 不收无关 note"
echo ""

echo -e "${bold}[游标推进]${reset}"
"$TTMUX" swarm listen listen-case --as master --once >/dev/null
empty_out=$("$TTMUX" swarm listen listen-case --as master --once)
assert_contains "$empty_out" "(没有新广场消息)" "游标推进后不重复吐旧消息"

"$TTMUX" swarm say listen-case --as human --to master --kind ask "第二条 human 指令" >/dev/null
next_out=$("$TTMUX" swarm listen listen-case --as master --once)
next_msgs=$(printf '%s\n' "$next_out" | message_section)
assert_contains "$next_msgs" "@master 第二条 human 指令" "游标后新消息仍可读取"
assert_not_contains "$next_msgs" "@master 补移动端验收" "新一轮不回放旧 human 消息"
echo ""

echo -e "${dim}$(printf '─%.0s' {1..44})${reset}"
total=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
    echo -e "${green}${bold}全部通过${reset} ${dim}(${total}/${total})${reset}"
else
    echo -e "${red}${bold}${FAIL} 个失败${reset} ${dim}(${PASS}/${total} 通过)${reset}"
fi
echo ""

exit "$FAIL"
