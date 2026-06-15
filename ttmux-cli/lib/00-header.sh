#!/usr/bin/env bash
#
# ttmux - AI-native tmux wrapper
# https://github.com/ybz21/ttmux
#
# ⚠ 本文件由 ttmux-cli/build.sh 自动生成，请勿直接编辑。
#   改 ttmux-cli/lib/*.sh 后运行 ttmux-cli/build.sh 重新生成。
#

set -euo pipefail

TTMUX_VERSION="0.4.0"
TMUX_BIN="$(command -v tmux)"
TTMUX_DATA="${TTMUX_DATA:-${HOME}/.local/share/ttmux}"
TTMUX_LOGS="${TTMUX_DATA}/logs"
TTMUX_GROUPS="${TTMUX_DATA}/groups"
TTMUX_ENV="${TTMUX_DATA}/env"
TTMUX_META="${TTMUX_DATA}/meta"
TTMUX_SWARMS="${TTMUX_DATA}/swarms"

mkdir -p "$TTMUX_LOGS" "$TTMUX_GROUPS" "$TTMUX_META" "$TTMUX_SWARMS"

