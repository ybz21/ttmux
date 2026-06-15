# ══════════════════════════════════════════
# ── swarm: 蜂群编排 ──
# ══════════════════════════════════════════
#
# 蜂群 = 一个有目标的任务组 + 元数据边车(goal/status/supervisor/deps)。
# 成员就是底层任务组 <swarm> 的会话(<swarm>-<member>)，
# 因此复用 _spawn_one / _status / _collect / _kill_group / _group_* 全套机制。
#
#   ${TTMUX_SWARMS}/<swarm>/
#   ├── goal.txt        目标(可空)
#   ├── status.txt      planning|running|integrating|done|archived
#   ├── supervisor.txt  指挥的 cc 会话名(可空)
#   ├── created.txt
#   └── deps/<member>.txt  依赖的成员名(逗号分隔, 仅有依赖时存在)

_swarm_dir()    { echo "${TTMUX_SWARMS}/${1}"; }
_swarm_exists() { [[ -d "$(_swarm_dir "$1")" ]]; }

# _swarm_meta_get <swarm> <key>   -> 输出值(无则空)
_swarm_meta_get() {
    local f="$(_swarm_dir "$1")/${2}.txt"
    [[ -f "$f" ]] && cat "$f" || true
}
# _swarm_meta_set <swarm> <key> <value>
_swarm_meta_set() {
    local dir; dir=$(_swarm_dir "$1")
    mkdir -p "$dir"
    printf '%s\n' "$3" > "${dir}/${2}.txt"
}

# 成员显示名: 去掉 "<swarm>-" 前缀
_swarm_member_name() {
    local swarm="$1" sess="$2"
    echo "${sess#"${swarm}"-}"
}

# 依赖读写
_swarm_dep_get() { local f="$(_swarm_dir "$1")/deps/${2}.txt"; [[ -f "$f" ]] && cat "$f" || true; }
_swarm_dep_set() {
    local dir="$(_swarm_dir "$1")/deps"
    mkdir -p "$dir"
    printf '%s\n' "$3" > "${dir}/${2}.txt"
}

# ── 命令 ──

# ttmux swarm new <名> [--goal "..."]
_swarm_new() {
    local name="$1"; shift || true
    [[ -n "$name" ]] || { msg_err "用法: ttmux swarm new <名> [--goal \"...\"]"; return 1; }
    if _swarm_exists "$name"; then
        msg_warn "蜂群 ${bold}${name}${reset} 已存在"
        return 1
    fi
    local goal=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --goal) goal="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    mkdir -p "$(_swarm_dir "$name")"
    _swarm_meta_set "$name" goal "$goal"
    _swarm_meta_set "$name" status "planning"
    _swarm_meta_set "$name" supervisor ""
    _swarm_meta_set "$name" created "$(date '+%Y-%m-%d %H:%M:%S')"
    msg_ok "蜂群 ${bold}${name}${reset} 已创建"
    [[ -n "$goal" ]] && echo -e "   ${dim}目标: ${goal}${reset}"
    echo -e "   ${dim}加成员: ttmux swarm add ${name} <名> --type agent \"<任务>\"${reset}"
}

# ttmux swarm add <群> <成员> [--type task|agent] [--dir/--perm/--model] [--depends-on a,b] <payload...>
_swarm_add() {
    local swarm="$1" member="$2"
    shift 2 2>/dev/null || { msg_err "用法: ttmux swarm add <群> <成员> [--type task|agent] <命令或任务>"; return 1; }
    if ! _swarm_exists "$swarm"; then
        msg_err "蜂群不存在: ${swarm}  ${dim}(先 ttmux swarm new ${swarm})${reset}"
        return 1
    fi
    [[ -n "$member" ]] || { msg_err "成员名不能为空"; return 1; }

    local type="agent" workdir model="" perm="" deps="" payload_parts=()
    _agent_defaults
    workdir="$AGENT_WORKDIR"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)       type="$2"; shift 2 ;;
            --dir)        workdir="$2"; shift 2 ;;
            --model)      model="$2"; shift 2 ;;
            --perm)       perm="$2"; shift 2 ;;
            --depends-on) deps="$2"; shift 2 ;;
            *)            payload_parts+=("$1"); shift ;;
        esac
    done
    local payload="${payload_parts[*]}"
    if [[ -z "$payload" ]]; then
        msg_err "缺少${type}内容: ${dim}命令(task) 或 任务描述(agent)${reset}"
        return 1
    fi
    if [[ "$type" != "task" && "$type" != "agent" ]]; then
        msg_err "--type 只能是 task 或 agent"
        return 1
    fi

    # agent 成员: 设置 AGENT_* 供 _agent_claude_cmd 使用
    if [[ "$type" == "agent" ]]; then
        AGENT_WORKDIR="$workdir"
        [[ -n "$model" ]] && AGENT_MODEL="$model"
        [[ -n "$perm" ]]  && AGENT_PERMISSION="$perm"
    fi

    # 成员 = 任务组 <swarm> 的会话；底层类型 agent 走 claude，task 走 shell
    if _spawn_one "$swarm" "$member" "$type" "$payload" "$workdir"; then
        [[ -n "$deps" ]] && _swarm_dep_set "$swarm" "$member" "$deps"
        _swarm_meta_set "$swarm" status "running"
        local suffix=""; (( ${#payload} > 60 )) && suffix="..."
        msg_ok "成员 ${bold}${member}${reset} (${type}): ${dim}${payload:0:60}${suffix}${reset}"
        [[ -n "$deps" ]] && echo -e "   ${dim}依赖: ${deps}${reset}"
        return 0
    fi
    return 1
}

# ttmux swarm ls
_swarm_ls() {
    shopt -s nullglob
    local dirs=("${TTMUX_SWARMS}"/*/)
    if [[ ${#dirs[@]} -eq 0 ]]; then
        msg_info "没有蜂群  ${dim}(ttmux swarm new <名> 创建)${reset}"
        return
    fi
    echo ""
    for d in "${dirs[@]}"; do
        local name; name=$(basename "$d")
        local goal status sup total=0 alive=0
        goal=$(_swarm_meta_get "$name" goal)
        status=$(_swarm_meta_get "$name" status)
        sup=$(_swarm_meta_get "$name" supervisor)
        while IFS= read -r sess; do
            [[ -n "$sess" ]] || continue
            ((total++)) || true
            _session_exists "$sess" && ((alive++)) || true
        done < <(_group_sessions "$name")
        # 状态着色
        local st_str
        case "$status" in
            running)     st_str="${yellow}running${reset}" ;;
            done)        st_str="${green}done${reset}" ;;
            integrating) st_str="${cyan}integrating${reset}" ;;
            archived)    st_str="${dim}archived${reset}" ;;
            *)           st_str="${dim}${status:-planning}${reset}" ;;
        esac
        echo -e "   ${icon_group} ${bold}${name}${reset}  ${dim}${alive}/${total} 活跃${reset}  ${st_str}$( [[ -n "$sup" ]] && echo "  ${magenta}◆${sup}${reset}" )"
        [[ -n "$goal" ]] && echo -e "       ${dim}${goal}${reset}"
    done
    echo ""
}

# ttmux swarm status <群>
_swarm_status() {
    local name="$1"
    if ! _swarm_exists "$name"; then msg_err "蜂群不存在: ${name}"; return 1; fi
    local goal status sup created
    goal=$(_swarm_meta_get "$name" goal)
    status=$(_swarm_meta_get "$name" status)
    sup=$(_swarm_meta_get "$name" supervisor)
    created=$(_swarm_meta_get "$name" created)
    echo ""
    echo -e "  ${magenta}◆${reset} ${bold}蜂群: ${name}${reset}   ${dim}[${status:-planning}]${reset}"
    [[ -n "$goal" ]]    && echo -e "    ${dim}目标:${reset} ${goal}"
    [[ -n "$sup" ]]     && echo -e "    ${dim}指挥:${reset} ${magenta}${sup}${reset}"
    [[ -n "$created" ]] && echo -e "    ${dim}创建:${reset} ${dim}${created}${reset}"
    # 成员状态 + 依赖
    while IFS= read -r sess; do
        [[ -n "$sess" ]] || continue
        local m dep
        m=$(_swarm_member_name "$name" "$sess")
        dep=$(_swarm_dep_get "$name" "$m")
        [[ -n "$dep" ]] && echo -e "    ${dim}└ ${m} 依赖→ ${dep}${reset}"
    done < <(_group_sessions "$name")
    # 复用任务组状态(逐会话 running/done)；还没有成员时不报错
    if _group_exists "$name"; then
        _status "$name" || true
    else
        echo -e "    ${dim}(还没有成员，用 a) 加成员)${reset}"
    fi
    return 0
}

# ttmux swarm collect <群> [--json]
_swarm_collect() {
    local name="$1" fmt="${2:-text}"
    if ! _swarm_exists "$name"; then msg_err "蜂群不存在: ${name}"; return 1; fi
    if ! _group_exists "$name"; then
        msg_info "蜂群 ${bold}${name}${reset} 还没有成员"
        return 0
    fi
    _collect "$name" "$fmt" || true
    return 0
}

# ttmux swarm adopt <群> [--by <cc会话>] [--dir <目录>]
# cc 接管：写 supervisor + 拉起(或复用)一个交互式 cc 会话并注入 /cc-swarm --swarm <群>
_swarm_adopt() {
    local swarm="$1"; shift || true
    if ! _swarm_exists "$swarm"; then msg_err "蜂群不存在: ${swarm}"; return 1; fi
    local cc="" dir; dir="$(pwd)"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --by)  cc="$2"; shift 2 ;;
            --dir) dir="$2"; shift 2 ;;
            *)     shift ;;
        esac
    done
    [[ -n "$cc" ]] || cc="cc-${swarm}"

    _swarm_meta_set "$swarm" supervisor "$cc"
    _swarm_meta_set "$swarm" status "running"

    local invoke="/cc-swarm --swarm ${swarm}"
    if _session_exists "$cc"; then
        # 复用已有 cc 会话：直接发指令
        "$TMUX_BIN" send-keys -t "$cc" "$invoke" C-m
        msg_ok "已让现有会话 ${bold}${cc}${reset} 接管蜂群 ${bold}${swarm}${reset}"
    else
        # 新建交互式 claude 会话作为指挥
        local claude_bin; claude_bin="$(command -v claude || echo claude)"
        "$TMUX_BIN" new-session -d -s "$cc" -x 220 -y 50
        _inject_env "$cc"
        "$TMUX_BIN" pipe-pane -t "$cc" -o "cat >> '${TTMUX_LOGS}/${cc}.log'"
        : > "${TTMUX_LOGS}/${cc}.log"
        # 用初始 prompt 直接拉起 cc-swarm 监护(交互式，便于审批/追加指令)
        "$TMUX_BIN" send-keys -t "$cc" "cd '${dir}' && ${claude_bin} '${invoke}'" C-m
        msg_ok "已拉起指挥会话 ${bold}${cc}${reset} 接管蜂群 ${bold}${swarm}${reset}"
    fi
    echo -e "   ${dim}附加查看:  ttmux a ${cc}${reset}"
    echo -e "   ${dim}若指挥未自动开始，附加后手动发:  ${invoke}${reset}"
}

# ttmux swarm done <群>  — 标记完成(不杀会话)
_swarm_done() {
    local name="$1"
    if ! _swarm_exists "$name"; then msg_err "蜂群不存在: ${name}"; return 1; fi
    _swarm_meta_set "$name" status "done"
    msg_ok "蜂群 ${bold}${name}${reset} 已标记完成"
}

# ttmux swarm archive <群> — 杀会话、保留元数据、置 archived
_swarm_archive() {
    local name="$1"
    if ! _swarm_exists "$name"; then msg_err "蜂群不存在: ${name}"; return 1; fi
    if _group_exists "$name"; then
        _kill_group "$name"   # 优雅退出 agent + 杀会话 + 清任务元数据 + 删 .group 文件
    fi
    _swarm_meta_set "$name" status "archived"
    msg_ok "蜂群 ${bold}${name}${reset} 已归档 ${dim}(会话已清，元数据保留)${reset}"
}

# ttmux swarm rm <群> — 彻底删除(杀会话 + 删全部元数据)
_swarm_rm() {
    local name="$1"
    if ! _swarm_exists "$name"; then msg_err "蜂群不存在: ${name}"; return 1; fi
    if ! _confirm "确定彻底删除蜂群 ${bold}${name}${reset}(含会话与元数据)?"; then
        msg_info "已取消"; return 0
    fi
    _group_exists "$name" && _kill_group "$name" >/dev/null 2>&1 || true
    rm -rf "$(_swarm_dir "$name")"
    msg_ok "蜂群 ${bold}${name}${reset} 已删除"
}

# ══════════════════════════════════════════
# ── 交互式：两层蜂群界面 ──
# ══════════════════════════════════════════

# 选一个蜂群（提示打到 stderr，选中名打到 stdout）
_pick_swarm() {
    local prompt="${1:-选择蜂群}"
    local swarms=()
    shopt -s nullglob
    for d in "${TTMUX_SWARMS}"/*/; do
        swarms+=("$(basename "$d")")
    done
    if [[ ${#swarms[@]} -eq 0 ]]; then
        msg_info "没有蜂群" >&2
        return 1
    fi
    if [[ ${#swarms[@]} -eq 1 ]]; then
        echo "${swarms[0]}"; return 0
    fi
    echo "" >&2
    echo -e "  ${bold}${prompt}:${reset}" >&2
    local i=1
    for s in "${swarms[@]}"; do
        echo -e "    ${cyan}${i}${reset}) ${s}  ${dim}[$(_swarm_meta_get "$s" status)]${reset}" >&2
        ((i++)) || true
    done
    echo "" >&2
    read -r -p "  编号: " choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#swarms[@]} )); then
        echo "${swarms[$((choice-1))]}"
    else
        return 1
    fi
}

# 第一层：新建蜂群
_interactive_swarm_new() {
    read -r -p "  蜂群名称: " sname </dev/tty
    [[ -n "$sname" ]] || return
    read -r -p "  目标 (可空): " sgoal </dev/tty
    echo ""
    if [[ -n "$sgoal" ]]; then
        _swarm_new "$sname" --goal "$sgoal"
    else
        _swarm_new "$sname"
    fi
    # 顺手问要不要进去加成员
    echo ""
    read -r -p "  现在进入该蜂群加成员? [Y/n]: " yn </dev/tty
    case "${yn:-y}" in
        n|N) ;;
        *) _interactive_swarm_detail "$sname" ;;
    esac
}

# 第二层：加成员
_interactive_swarm_add_member() {
    local swarm="$1"
    read -r -p "  成员名称: " mname </dev/tty
    [[ -n "$mname" ]] || return
    echo -e "  ${bold}类型:${reset}  ${cyan}1${reset}) shell 命令   ${cyan}2${reset}) Claude Agent"
    read -r -p "  选择 [2]: " mt </dev/tty
    echo ""
    if [[ "${mt:-2}" == "1" ]]; then
        read -r -p "  命令: " mcmd </dev/tty
        [[ -n "$mcmd" ]] || { msg_warn "命令为空，取消"; return; }
        read -r -p "  依赖成员 (逗号分隔, 可空): " mdep </dev/tty
        if [[ -n "$mdep" ]]; then
            _swarm_add "$swarm" "$mname" --type task --depends-on "$mdep" "$mcmd"
        else
            _swarm_add "$swarm" "$mname" --type task "$mcmd"
        fi
    else
        read -r -p "  任务描述: " mtask </dev/tty
        [[ -n "$mtask" ]] || { msg_warn "任务为空，取消"; return; }
        read -r -p "  工作目录 [$(pwd)]: " mdir </dev/tty
        mdir="${mdir:-$(pwd)}"
        read -r -p "  权限 (auto/plan/default) [auto]: " mperm </dev/tty
        mperm="${mperm:-auto}"
        read -r -p "  依赖成员 (逗号分隔, 可空): " mdep </dev/tty
        local args=("$swarm" "$mname" --type agent --dir "$mdir" --perm "$mperm")
        [[ -n "$mdep" ]] && args+=(--depends-on "$mdep")
        args+=("$mtask")
        _swarm_add "${args[@]}"
    fi
}

# 第二层：对某成员追加指令
_interactive_swarm_send() {
    local swarm="$1"
    local members=()
    while IFS= read -r sess; do
        [[ -n "$sess" ]] || continue
        members+=("$sess")
    done < <(_group_sessions "$swarm")
    if [[ ${#members[@]} -eq 0 ]]; then msg_info "该蜂群还没有成员"; return; fi
    echo ""
    echo -e "  ${bold}成员:${reset}"
    local i=1
    for m in "${members[@]}"; do
        local run; _session_exists "$m" && run=" ${yellow}运行中${reset}" || run=" ${dim}已结束${reset}"
        echo -e "    ${cyan}${i}${reset}) $(_swarm_member_name "$swarm" "$m")${run}"
        ((i++)) || true
    done
    echo ""
    read -r -p "  选择成员编号: " choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#members[@]} )); then
        read -r -p "  追加指令: " msg </dev/tty
        [[ -n "$msg" ]] && _task_send "${members[$((choice-1))]}" "$msg"
    else
        msg_err "无效选择"
    fi
}

# 第二层主循环：蜂群详情 / 成员管理
_interactive_swarm_detail() {
    local swarm="$1"
    while true; do
        clear
        _swarm_status "$swarm"
        echo ""
        echo -e "  ${bold}蜂群 ${swarm} ─ 成员管理${reset}"
        echo -e "    ${cyan}a${reset}) 加成员            ${cyan}m${reset}) 追加指令"
        echo -e "    ${cyan}c${reset}) 等待并收集        ${cyan}k${reset}) 清理整群"
        echo -e "    ${cyan}d${reset}) cc 接管           ${cyan}b${reset}) 返回上层"
        echo ""
        read -r -p "  选择: " act </dev/tty
        echo ""
        case "$act" in
            a) _interactive_swarm_add_member "$swarm" || true; _interactive_pause ;;
            m) _interactive_swarm_send "$swarm" || true; _interactive_pause ;;
            c) _do_wait_group "$swarm" 300 || true; echo ""; _swarm_collect "$swarm" text || true; _interactive_pause ;;
            k)
                if _confirm "清理整群 ${bold}${swarm}${reset} (杀全部成员会话)?"; then
                    _swarm_archive "$swarm" || true
                fi
                _interactive_pause; return ;;
            d) _swarm_adopt "$swarm" || true; _interactive_pause ;;
            b|q|"") return ;;
            *) msg_warn "无效选择"; _interactive_pause ;;
        esac
    done
}

# 第一层主循环：蜂群管理
_interactive_swarm() {
    while true; do
        clear
        echo ""
        echo -e "  ${bold}任务编排 ${magenta}(蜂群 / swarm)${reset}"
        echo -e "  ${dim}$(printf '─%.0s' {1..44})${reset}"
        _swarm_ls
        echo -e "    ${cyan}n${reset}) 新建蜂群          ${cyan}e${reset}) 进入蜂群 ▸"
        echo -e "    ${cyan}d${reset}) cc 接管蜂群       ${cyan}x${reset}) 归档/删除蜂群"
        echo -e "    ${cyan}b${reset}) 返回主菜单"
        echo ""
        read -r -p "  选择: " act </dev/tty
        echo ""
        case "$act" in
            n) _interactive_swarm_new || true; _interactive_pause ;;
            e)
                local s; s=$(_pick_swarm "进入蜂群") || { _interactive_pause; continue; }
                _interactive_swarm_detail "$s" || true ;;
            d)
                local s; s=$(_pick_swarm "cc 接管") || { _interactive_pause; continue; }
                _swarm_adopt "$s" || true; _interactive_pause ;;
            x)
                local s; s=$(_pick_swarm "归档/删除") || { _interactive_pause; continue; }
                echo -e "  ${cyan}1${reset}) 归档(留元数据)  ${cyan}2${reset}) 彻底删除  ${cyan}0${reset}) 取消"
                read -r -p "  选择: " xa </dev/tty
                case "$xa" in
                    1) _swarm_archive "$s" || true ;;
                    2) _swarm_rm "$s" || true ;;
                esac
                _interactive_pause ;;
            b|q|"") return ;;
            *) msg_warn "无效选择"; _interactive_pause ;;
        esac
    done
}
