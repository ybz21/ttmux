package swarm

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"ttmux-cli-go/internal/command/spawn"
	"ttmux-cli-go/internal/runtime"
	swarmcore "ttmux-cli-go/internal/swarm"
	"ttmux-cli-go/internal/ui"
)

// launchMember spawns a member session, building the agent config from its spec.
func launchMember(rt runtime.Runtime, swarm string, m swarmcore.MemberSpec, w io.Writer) (bool, error) {
	ac := spawn.DefaultAgentConfig(m.Workdir)
	if m.Type == "agent" {
		ac.Kind = m.Kind
		ac.Interactive = true
		if m.Model != "" {
			ac.Model = m.Model
		}
		if m.Perm != "" {
			ac.Permission = m.Perm
		}
	}
	return spawn.One(rt, swarm, m.Name, m.Type, m.Task, ac, w)
}

// spawnCallback adapts launchMember to the core's SpawnFunc signature.
func spawnCallback(rt runtime.Runtime, w io.Writer) swarmcore.SpawnFunc {
	return func(swarm string, m swarmcore.MemberSpec) (bool, error) {
		return launchMember(rt, swarm, m, w)
	}
}

func claudeBin() string {
	if p, err := exec.LookPath("claude"); err == nil {
		return p
	}
	return "claude"
}

func hasClaude() bool {
	_, err := exec.LookPath("claude")
	return err == nil
}

func shellQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

// adopt writes supervisor metadata and brings up (or reuses) a cc-<swarm>
// commander session running /cc-swarm (mirrors _swarm_adopt).
func adopt(rt runtime.Runtime, st *swarmcore.Store, swarm, cc, dir string, w io.Writer) error {
	if !st.Exists(swarm) {
		ui.Err(w, "蜂群不存在: %s", swarm)
		return fmt.Errorf("not found")
	}
	if cc == "" {
		cc = "cc-" + st.Name(swarm)
	}
	if dir == "" {
		dir = "."
	}
	if dir != "." {
		_ = os.MkdirAll(dir, 0o755)
	}
	_ = st.MetaSet(swarm, "supervisor", cc)
	_ = st.MetaSet(swarm, "status", "running")
	goal := st.MetaGet(swarm, "goal")
	invoke := "/cc-swarm --swarm " + swarm
	if goal != "" {
		invoke += " " + goal
	}
	if rt.HasSession(cc) {
		_ = rt.Tmux("send-keys", "-t", cc, invoke, "C-m")
		ui.Ok(w, "已让现有会话 %s 接管蜂群 %s", ui.Bold(cc), ui.Bold(swarm))
		return nil
	}
	_ = rt.Tmux("new-session", "-d", "-s", cc, "-x", "220", "-y", "50")
	rt.InjectEnv(cc)
	_ = rt.Tmux("pipe-pane", "-t", cc, "-o", "cat >> '"+rt.LogFile(cc)+"'")
	_ = writeEmpty(rt.LogFile(cc))
	runCmd := "cd '" + dir + "' && " + claudeBin() + " " + shellQuote(invoke)
	_ = rt.Tmux("send-keys", "-t", cc, runCmd, "C-m")
	ui.Ok(w, "已拉起指挥会话 %s 接管蜂群 %s", ui.Bold(cc), ui.Bold(swarm))
	if goal != "" {
		fmt.Fprintf(w, "   %s目标已交给指挥: %s%s\n", ui.P().Dim, goal, ui.P().Reset)
	}
	return nil
}

func cmdAdopt(rt runtime.Runtime, st *swarmcore.Store, args []string, w io.Writer) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: ttmux swarm adopt <name> [--by <session>] [--dir <dir>]")
	}
	swarm := args[0]
	cc, dir := "", "."
	for i := 1; i < len(args); i++ {
		switch args[i] {
		case "--by":
			cc, i = next(args, i)
		case "--dir":
			dir, i = next(args, i)
		}
	}
	return adopt(rt, st, swarm, cc, dir, w)
}

type swarmListItem struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Goal       string `json:"goal"`
	Status     string `json:"status"`
	Supervisor string `json:"supervisor"`
	Created    string `json:"created"`
	Total      int    `json:"total"`
	Alive      int    `json:"alive"`
	Pending    int    `json:"pending"`
}

func cmdList(rt runtime.Runtime, st *swarmcore.Store, args []string, w io.Writer) error {
	jsonOut := len(args) > 0 && args[0] == "--json"
	swarms, err := st.ListSwarms()
	if err != nil {
		return err
	}
	if jsonOut {
		items := []swarmListItem{}
		for _, s := range swarms {
			total, alive := groupCounts(rt, s.Name)
			items = append(items, swarmListItem{
				ID: s.ID, Name: s.Name, Goal: s.Goal, Status: s.Status,
				Supervisor: s.Supervisor, Created: s.Created,
				Total: total, Alive: alive, Pending: st.PendingCount(s.Name),
			})
		}
		return json.NewEncoder(w).Encode(items)
	}
	if len(swarms) == 0 {
		ui.Info(w, "没有蜂群  %s", ui.Dim("(ttmux swarm new <名> 创建)"))
		return nil
	}
	p := ui.P()
	fmt.Fprintln(w)
	for _, s := range swarms {
		total, alive := groupCounts(rt, s.Name)
		st_str := p.Dim + orStr(s.Status, "planning") + p.Reset
		switch s.Status {
		case "running":
			st_str = p.Yellow + "running" + p.Reset
		case "done":
			st_str = p.Green + "done" + p.Reset
		case "integrating":
			st_str = p.Cyan + "integrating" + p.Reset
		case "archived":
			st_str = p.Dim + "archived" + p.Reset
		}
		pend := st.PendingCount(s.Name)
		pendStr := ""
		if pend > 0 {
			pendStr = fmt.Sprintf("  %s+%d待解锁%s", p.Yellow, pend, p.Reset)
		}
		sup := ""
		if s.Supervisor != "" {
			sup = fmt.Sprintf("  %s◆%s%s", p.Magenta, s.Supervisor, p.Reset)
		}
		fmt.Fprintf(w, "   %s %s  %s%d/%d 活跃%s%s  %s%s\n",
			ui.IconGroup, ui.Bold(s.Name), p.Dim, alive, total, p.Reset, pendStr, st_str, sup)
		if s.Goal != "" {
			fmt.Fprintf(w, "       %s%s%s\n", p.Dim, s.Goal, p.Reset)
		}
	}
	fmt.Fprintf(w, "  %s钻取: ttmux swarm status <群>(含看板/广场) · board <群> · feed <群>%s\n\n", p.Dim, p.Reset)
	return nil
}

func cmdSQL(st *swarmcore.Store, args []string, w io.Writer) error {
	if len(args) < 1 {
		return fmt.Errorf(`usage: ttmux swarm sql <name> [--json] "SELECT ..."`)
	}
	name := args[0]
	args = args[1:]
	jsonOut := false
	if len(args) > 0 && args[0] == "--json" {
		jsonOut = true
		args = args[1:]
	}
	if len(args) < 1 || strings.TrimSpace(args[0]) == "" {
		return fmt.Errorf(`usage: ttmux swarm sql <name> [--json] "SELECT ..."`)
	}
	q := args[0]
	head := strings.ToLower(strings.TrimSpace(q))
	allowed := false
	for _, pfx := range []string{"select", "pragma", "explain", "with", ".tables", ".schema"} {
		if strings.HasPrefix(head, pfx) {
			allowed = true
			break
		}
	}
	if !allowed {
		ui.Err(w, "只读逃生口：仅允许 SELECT/PRAGMA/EXPLAIN/WITH/.tables/.schema")
		return fmt.Errorf("readonly guard")
	}
	cols, rows, err := st.ReadQuery(name, q)
	if err != nil {
		return err
	}
	if jsonOut {
		out := make([]map[string]string, 0, len(rows))
		for _, r := range rows {
			m := map[string]string{}
			for i, c := range cols {
				m[c] = r[i]
			}
			out = append(out, m)
		}
		return json.NewEncoder(w).Encode(out)
	}
	fmt.Fprintln(w, strings.Join(cols, "|"))
	for _, r := range rows {
		fmt.Fprintln(w, strings.Join(r, "|"))
	}
	return nil
}

func groupCounts(rt runtime.Runtime, group string) (total, alive int) {
	sessions, _ := rt.GroupSessions(group)
	for _, s := range sessions {
		total++
		if rt.HasSession(s) {
			alive++
		}
	}
	return
}

func writeEmpty(path string) error { return os.WriteFile(path, nil, 0o644) }

func out(s string, _ error) string { return s }

func orStr(s, def string) string {
	if s == "" {
		return def
	}
	return s
}
