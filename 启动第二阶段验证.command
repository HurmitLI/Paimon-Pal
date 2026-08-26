#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
"$PROJECT_ROOT/scripts/build_and_open_notchflow.sh"
