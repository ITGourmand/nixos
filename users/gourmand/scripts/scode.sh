#!/usr/bin/env bash

dir=$(mktemp -d /tmp/vscode-root.XXXXXX)

sudo setsid -f sh -c '
  code --user-data-dir "$0" --no-sandbox --wait "$@"
  rm -rf "$0"
' "$dir" "$@" >/dev/null 2>&1 </dev/null