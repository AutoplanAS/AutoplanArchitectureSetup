#!/usr/bin/env bash
set -euo pipefail

mode="auto"
force="0"
install_blueprint="0"
targets_csv="copilot"

usage() {
  cat <<'EOF'
Usage: install-autoplan-skills.sh [options]

Options:
  --targets <csv>          Target agents: copilot,claude,codex,gemini (default: copilot)
  --mode <auto|symlink|copy>
  --force                  Replace existing skill directories
  --install-blueprint      Run `npx skills add owainlewis/blueprint`
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)
      targets_csv="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --force)
      force="1"
      shift
      ;;
    --install-blueprint)
      install_blueprint="1"
      shift
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

case "$mode" in
  auto|symlink|copy) ;;
  *)
    echo "Invalid --mode: $mode" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
machinist_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$machinist_dir/.." && pwd)"

map_target_root() {
  case "$1" in
    copilot) echo "$HOME/.agents/skills" ;;
    claude) echo "$HOME/.claude/skills" ;;
    codex) echo "$HOME/.codex/skills" ;;
    gemini) echo "$HOME/.gemini/skills" ;;
    *)
      echo "Unsupported target: $1" >&2
      exit 1
      ;;
  esac
}

install_skill() {
  local source_dir="$1"
  local target_root="$2"
  local skill_name
  local target_dir
  local marker

  skill_name="$(basename "$source_dir")"
  target_dir="$target_root/$skill_name"
  marker="$target_dir/.autoplan-skill-source"

  mkdir -p "$target_root"

  if [[ -e "$target_dir" || -L "$target_dir" ]]; then
    if [[ -L "$target_dir" ]]; then
      local link_target
      link_target="$(readlink "$target_dir" || true)"
      if [[ "$link_target" == "$source_dir" ]]; then
        echo "  = $skill_name (already linked)"
        return 0
      fi
    fi

    if [[ "$force" == "1" ]]; then
      rm -rf "$target_dir"
    elif [[ -f "$marker" && "$(cat "$marker")" == "$source_dir" ]]; then
      rm -rf "$target_dir"
    else
      echo "  ! $skill_name exists in $target_root (use --force to replace)" >&2
      return 1
    fi
  fi

  if [[ "$mode" == "symlink" || "$mode" == "auto" ]]; then
    if ln -s "$source_dir" "$target_dir" 2>/dev/null; then
      echo "  + $skill_name (symlink)"
      return 0
    fi
    if [[ "$mode" == "symlink" ]]; then
      echo "  ! Failed to symlink $skill_name" >&2
      return 1
    fi
  fi

  cp -R "$source_dir" "$target_dir"
  printf '%s' "$source_dir" > "$marker"
  echo "  + $skill_name (copy)"
}

declare -a skill_dirs=()
while IFS= read -r path; do
  [[ -f "$path/SKILL.md" ]] || continue
  skill_dirs+=("$path")
done < <(
  find "$repo_root/autoplan-backend-skills/skills" "$repo_root/autoplan-webapp-skills/skills" \
    -mindepth 1 -maxdepth 1 -type d -name 'autoplan-*' | sort
)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  echo "No skill directories found under backend/webapp skill packages." >&2
  exit 1
fi

IFS=',' read -r -a targets <<< "$targets_csv"
for target in "${targets[@]}"; do
  normalized_target="$(echo "$target" | tr '[:upper:]' '[:lower:]' | xargs)"
  [[ -n "$normalized_target" ]] || continue
  target_root="$(map_target_root "$normalized_target")"
  echo "Installing skills to $normalized_target ($target_root)"
  for skill_dir in "${skill_dirs[@]}"; do
    install_skill "$skill_dir" "$target_root"
  done
done

if [[ "$install_blueprint" == "1" ]]; then
  if ! command -v npx >/dev/null 2>&1; then
    echo "npx not found; install Node.js/npm before using --install-blueprint." >&2
    exit 1
  fi
  npx skills add owainlewis/blueprint
fi

echo "Autoplan skill installation complete."
