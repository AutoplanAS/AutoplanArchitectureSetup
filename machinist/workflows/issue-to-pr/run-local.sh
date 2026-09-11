#!/usr/bin/env bash
set -euo pipefail

prompt=""
command_name="autoplan-factory-foreman"
model="terra"
worker_config=""
machinist_config=""
repository_path=""

usage() {
  cat <<'EOF'
Usage: run-local.sh --prompt "<work request>" [options]

Options:
  --command <name>            Command name (default: autoplan-factory-foreman)
  --model <alias>             Executor model alias (default: terra)
  --repo <path>               Repository path (default: repo root)
  --worker-config <path>      Worker config path (default: machinist/worker.toml.example)
  --machinist-config <path>   Machinist config path (default: machinist/config.toml.example)
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      prompt="${2:-}"
      shift 2
      ;;
    --command)
      command_name="${2:-}"
      shift 2
      ;;
    --model)
      model="${2:-}"
      shift 2
      ;;
    --repo)
      repository_path="${2:-}"
      shift 2
      ;;
    --worker-config)
      worker_config="${2:-}"
      shift 2
      ;;
    --machinist-config)
      machinist_config="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$prompt" ]]; then
  echo "--prompt is required." >&2
  usage >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
issue_to_pr_dir="$(cd "$script_dir" && pwd)"
workflows_dir="$(cd "$issue_to_pr_dir/.." && pwd)"
machinist_dir="$(cd "$workflows_dir/.." && pwd)"
repo_root="$(cd "$machinist_dir/.." && pwd)"

if [[ -z "$repository_path" ]]; then
  repository_path="$repo_root"
fi

if [[ -z "$worker_config" ]]; then
  worker_config="$machinist_dir/worker.toml.example"
fi

if [[ -z "$machinist_config" ]]; then
  machinist_config="$machinist_dir/config.toml.example"
fi

machinist run \
  --config "$worker_config" \
  --machinist-config "$machinist_config" \
  --command "$command_name" \
  --model "$model" \
  --repo "$repository_path" \
  --prompt "$prompt"
