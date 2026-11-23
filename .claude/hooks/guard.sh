#!/usr/bin/env bash
# PreToolUse guard: blocks delete / install commands and reading .env files.
# Exit 2 = block the tool call; stderr is shown to Claude as the reason.
set -u

block() {
  echo "Blocked by .claude/hooks/guard.sh: $1" >&2
  exit 2
}

# Without jq: block only what cannot be inspected (Bash) and obvious .env access; allow the rest.
if ! command -v jq >/dev/null 2>&1; then
  IFS= read -r -d '' input || true
  # Pure bash regex (no external commands) so a missing grep cannot make this pass silently.
  env_re='\.env(\.[A-Za-z0-9_-]+)*"'
  bash_re='"tool_name"[[:space:]]*:[[:space:]]*"Bash"'
  [[ "${input//.env.example/}" =~ $env_re ]] && block "possible .env access (jq not installed)"
  [[ "$input" =~ $bash_re ]] && block "jq not installed; Bash commands cannot be inspected"
  exit 0
fi

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"

# Matches .env, .env.local, .env.production, ... but not .env.example / process.env / .envrc
ENV_RE='(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_.-]+)?($|[^A-Za-z0-9_.-])'

is_env_path() {
  local base
  base="$(basename -- "$1")"
  [[ "$base" == ".env.example" ]] && return 1
  [[ "$base" =~ ^\.env(\..+)?$ ]]
}

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    S="(^|[;&|(\`\"'[:space:]])"   # command boundary (incl. quotes for bash -c "...")

    # --- delete ---
    grep -qE "${S}(sudo[[:space:]]+)?(rm|rmdir|unlink|shred)([[:space:]]|$)" <<<"$cmd" && block "delete command (rm/rmdir/unlink/shred)"
    grep -qE "${S}git[[:space:]]+(rm|clean)([[:space:]]|$)" <<<"$cmd" && block "git rm / git clean"
    grep -qE "${S}git[[:space:]]+branch[[:space:]]+.*(-D|--delete)" <<<"$cmd" && block "git branch delete"
    grep -qE "${S}git[[:space:]]+push([[:space:]].*)?[[:space:]](--force(-with-lease)?|-f|--delete|-d)([[:space:]]|=|$)" <<<"$cmd" && block "git push --force / --delete"
    grep -qE "${S}find[[:space:]].*-delete" <<<"$cmd" && block "find -delete"

    # --- install (pnpm install is allowed) ---
    grep -qE "${S}pnpm[[:space:]]+(-g[[:space:]]+|--global[[:space:]]+)?(add|dlx|up|update|upgrade)([[:space:]]|$)" <<<"$cmd" && block "pnpm add/dlx/up"
    grep -qE "${S}(npm|yarn|bun)[[:space:]]+(install|i|add|ci|dlx)([[:space:]]|$)" <<<"$cmd" && block "npm/yarn/bun install"
    grep -qE "${S}(npx|pnpx|pnx|bunx)([[:space:]]|$)" <<<"$cmd" && block "npx/pnpx/pnx/bunx"
    grep -qE "${S}(pip|pip3|pipx|uv[[:space:]]+pip)[[:space:]]+install" <<<"$cmd" && block "pip install"
    grep -qE "${S}(sudo[[:space:]]+)?(apt|apt-get|yum|dnf|apk)[[:space:]]+(install|add)" <<<"$cmd" && block "system package install"
    grep -qE "${S}brew[[:space:]]+install" <<<"$cmd" && block "brew install"

    # --- .env read ---
    stripped="${cmd//.env.example/}"
    grep -qE "$ENV_RE" <<<"$stripped" && block "command references a .env file"
    ;;

  Read|Edit|Write|NotebookEdit|Grep|Glob)
    for key in file_path notebook_path path; do
      p="$(jq -r ".tool_input.${key} // \"\"" <<<"$input")"
      [[ -n "$p" ]] && is_env_path "$p" && block "access to .env file ($p)"
    done
    ;;
esac

exit 0