#!/bin/sh
# macOS / Linux：需要 Node.js 20+，并且本机可用 `dsh` 命令
# （或安装 DeepSeek Harness Desktop，并在 bridge/config.json 里指定 dsh.command）。
set -e
cd "$(dirname "$0")"
exec node server.mjs "$@"
