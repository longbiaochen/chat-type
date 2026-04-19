#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/post_x.sh [--app APP_NAME] [--print] "post text"
  echo "post text" | scripts/post_x.sh [--app APP_NAME]

Options:
  --app APP_NAME  Use a specific xurl app profile.
  --print         Print the resolved xurl command without sending the post.
  -h, --help      Show this help message.

Notes:
  - Requires the official `xurl` CLI to be installed and authenticated.
  - Reads post text from the first positional argument or stdin.
  - Uses `XURL_APP` when `--app` is not provided.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

app_name="${XURL_APP:-}"
print_only=0
text=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      if [[ $# -lt 2 ]]; then
        echo "--app requires a value" >&2
        exit 1
      fi
      app_name="$2"
      shift 2
      ;;
    --print)
      print_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      text="$1"
      shift
      if [[ $# -gt 0 ]]; then
        echo "unexpected extra arguments" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$text" && $# -gt 0 ]]; then
  text="$1"
fi

if [[ -z "$text" && ! -t 0 ]]; then
  text="$(cat)"
fi

if [[ -z "$text" ]]; then
  echo "missing post text" >&2
  usage >&2
  exit 1
fi

require_cmd xurl

cmd=(xurl)
if [[ -n "$app_name" ]]; then
  cmd+=(--app "$app_name")
fi
cmd+=(post "$text")

if [[ "$print_only" -eq 1 ]]; then
  printf 'Resolved command:\n'
  printf '  '
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

"${cmd[@]}"
