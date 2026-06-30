#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/post_x.sh [--print] "post text"
  echo "post text" | scripts/post_x.sh [--print]

Options:
  --print         Print the official Chrome plugin workflow without sending the post.
  -h, --help      Show this help message.

Notes:
  - Reads post text from the first positional argument or stdin.
  - Live posting must be done through the official Chrome plugin in the signed-in browser.
  - This CLI only prints the required manual/plugin workflow and refuses legacy automation.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

print_only=0
text=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ "$print_only" -eq 1 ]]; then
  cat <<EOF
Resolved workflow:
  transport: official Chrome plugin
  browser: signed-in Chrome/default profile
  compose_url: https://x.com/compose/post
  post_text: $text
  verification: open the profile and confirm a fresh /status/ URL containing the post text
EOF
  exit 0
fi

cat >&2 <<'EOF'
Live X posting from scripts/post_x.sh is disabled.
Use the official Chrome plugin with the signed-in browser, then verify the new post on the profile page.
EOF
exit 2
