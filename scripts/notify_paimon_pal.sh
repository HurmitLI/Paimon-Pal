#!/bin/zsh
set -euo pipefail

source_name="${1:-codex}"
event_title="${2:-任务已完成}"
project_name="${3:-}"
task_id="${4:-}"

case "$source_name" in
  codex|claude|gpt) ;;
  *)
    print -u2 "source 必须是 codex、claude 或 gpt"
    exit 2
    ;;
esac

payload=$(/usr/bin/python3 - "$event_title" "$project_name" "$task_id" <<'PY'
import json
import sys

title, project, task_id = sys.argv[1:4]
payload = {"title": title}
if project:
    payload["project"] = project
if task_id:
    payload["task_id"] = task_id
print(json.dumps(payload, ensure_ascii=False))
PY
)

/usr/bin/curl --fail --silent --show-error \
  --request POST "http://127.0.0.1:43821/notify/${source_name}" \
  --header 'Content-Type: application/json' \
  --data "$payload"
print
