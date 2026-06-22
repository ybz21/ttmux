package swarm

import (
	"fmt"
	"io"

	"ttmux-cli-go/internal/runtime"
	swarmcore "ttmux-cli-go/internal/swarm"
)

func Run(rt runtime.Runtime, args []string, w io.Writer) error {
	subcmd := "ls"
	if len(args) > 0 {
		subcmd = args[0]
		args = args[1:]
	}
	switch subcmd {
	case "status":
		if len(args) < 1 {
			return fmt.Errorf("usage: ttmux swarm status <name> [--json]")
		}
		if len(args) > 1 && args[1] == "--json" {
			out, err := swarmcore.StatusJSON(args[0], swarmcore.Options{
				HomeDir: rt.HomeDir,
				DataDir: rt.DataDir,
				TmuxBin: rt.TmuxBin,
				Now:     rt.Now,
			})
			if err != nil {
				return err
			}
			_, err = fmt.Fprintln(w, string(out))
			return err
		}
		return rt.Shell(append([]string{"swarm", subcmd}, args...)...)
	case "new", "create", "migrate", "add", "ls", "list", "collect", "activate", "adopt", "done", "sql",
		"say", "listen", "feed", "watch", "board", "task", "archive", "rm", "delete":
		return rt.Shell(append([]string{"swarm", subcmd}, args...)...)
	default:
		return fmt.Errorf("unknown subcommand: swarm %s", subcmd)
	}
}
