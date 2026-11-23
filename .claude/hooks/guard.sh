#!/usr/bin/env bash
# PreToolUse guard: blocks delete / destructive git / install / secret access / guard tampering.
# Exit 2 = block the tool call; stderr is shown to Claude as the reason.
# ask() = require user confirmation (JSON permissionDecision "ask").
set -u

block() {
  echo "Blocked by .claude/hooks/guard.sh: $1" >&2
  exit 2
}

ASK_REASON=""
ask() { [[ -z "$ASK_REASON" ]] && ASK_REASON="$1"; }

emit_ask_or_allow() {
  if [[ -n "$ASK_REASON" ]]; then
    jq -n --arg r "guard.sh: $ASK_REASON" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  fi
  exit 0
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
# Fail closed: unparsable input is blocked instead of silently allowed.
tool="$(jq -er '.tool_name' <<<"$input" 2>/dev/null)" || block "failed to parse hook input"

# Matches .env, .env.local, .env.production, ... but not .env.example / process.env / .envrc
ENV_RE='(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_.-]+)?($|[^A-Za-z0-9_.-])'
# Glob tricks that can expand to .env: .e?v  .en*  .*  .[e]nv  .{env,x}
ENV_GLOB_RE='(^|[^A-Za-z0-9_.])\.(e[A-Za-z]*)?[*?[{]'
# Credentials outside the repo
SECRET_RE='(^|[^A-Za-z0-9_])(\.ssh/|\.ssh$|\.config/gh|\.git-credentials|\.claude/\.credentials|\.netrc|\.aws/|\.docker/config\.json)'
# Guard / git-hook files whose modification would disable or bypass this guard
PROTECT_RE='(^|/)\.claude/(settings(\.local)?\.json|hooks(/|$))|(^|/)\.git/(hooks(/|$)|config$)'

is_env_path() {
  local base
  base="$(basename -- "$1")"
  [[ "$base" == ".env.example" ]] && return 1
  [[ "$base" =~ ^\.env(\..+)?$ ]]
}
is_secret_path()    { [[ "$1" =~ $SECRET_RE ]]; }
is_protected_path() { [[ "$1" =~ $PROTECT_RE ]]; }

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    # Command boundary: start, separators, quotes (bash -c "..."), '/' (/bin/rm), '\' (\rm), '{'
    S="(^|[;&|(\`\"'{[:space:]/\\\\])"
    m() { grep -qE -- "$1" <<<"$cmd"; }

    # --- delete (irreversible) ---
    m "${S}(sudo[[:space:]]+)?(rm|rmdir|unlink|shred|truncate|srm|wipe)([[:space:]]|$)" && block "delete command (rm/rmdir/unlink/shred/truncate)"
    m "${S}find[[:space:]].*-delete" && block "find -delete"
    m "${S}mv[[:space:]].*/dev/null" && block "mv to /dev/null"
    m "(shutil\.rmtree|os\.(remove|unlink|rmdir|removedirs)|\.unlink\(|unlinkSync|rmSync|rmdirSync|fs\.rm\(|FileUtils\.rm|File\.delete)" && block "file deletion via scripting language"

    # --- destructive git (irreversible) ---
    m "${S}git[[:space:]]+(rm|clean)([[:space:]]|$)" && block "git rm / git clean"
    m "${S}git[[:space:]]+branch[[:space:]]+.*(-D|--delete)" && block "git branch delete"
    m "${S}git[[:space:]]+push([[:space:]].*)?[[:space:]](--force(-with-lease|-if-includes)?|--delete|--mirror|--prune|-[A-Za-z]*[fd][A-Za-z]*)([[:space:]]|=|$)" && block "git push --force / --delete / --mirror"
    m "${S}git[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+[+:][^[:space:]]" && block "git push with +refspec (force) or :refspec (delete)"
    m "${S}git[[:space:]]+(filter-branch|filter-repo|update-ref[[:space:]]+-d|reflog[[:space:]]+(expire|delete))" && block "git history rewrite / ref deletion"
    m "${S}git[[:space:]]+gc([[:space:]].*)?--prune" && block "git gc --prune"

    # --- guard tampering (git config that runs arbitrary code, protected files) ---
    m "${S}git[[:space:]]+(.*[[:space:]])?(config|-c)[[:space:]=].*(core\.(hooksPath|fsmonitor|sshCommand|pager|editor|askPass)|alias\.|credential\.|include\.|includeIf\.)" && block "git config that can execute arbitrary commands"
    m "GIT_(CONFIG_(COUNT|KEY_|VALUE_|PARAMETERS)|SSH_COMMAND|EXEC_PATH|ASKPASS)" && block "git env override"
    m "\.claude/(settings(\.local)?\.json|hooks)|\.git/(hooks|config)" && block "access to protected guard / git hook files"

    # --- install (pnpm install is allowed, but requires confirmation via settings.json) ---
    m "${S}pnpm[[:space:]]+(-g[[:space:]]+|--global[[:space:]]+)?(add|dlx|up|update|upgrade)([[:space:]]|$)" && block "pnpm add/dlx/up"
    m "${S}(npm|yarn|bun)[[:space:]]+(install|i|add|ci|dlx)([[:space:]]|$)" && block "npm/yarn/bun install"
    m "${S}(npx|pnpx|pnx|bunx|uvx)([[:space:]]|$)" && block "npx/pnpx/pnx/bunx/uvx"
    m "${S}(pip|pip3|pipx|uv[[:space:]]+pip)[[:space:]]+install" && block "pip install"
    m "${S}uv[[:space:]]+(add|tool[[:space:]]+install)" && block "uv add / uv tool install"
    m "${S}(cargo|go|gem)[[:space:]]+install" && block "cargo/go/gem install"
    m "${S}(sudo[[:space:]]+)?(apt|apt-get|yum|dnf|apk)[[:space:]]+(install|add)" && block "system package install"
    m "${S}brew[[:space:]]+install" && block "brew install"
    m "(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?((ba|z|da|k)?sh|python3?|node|perl|ruby)([[:space:]]|$)" && block "pipe remote script to interpreter"
    m "<\([[:space:]]*(curl|wget)|\\\$\([[:space:]]*(curl|wget)" && block "execute remote script via process/command substitution"

    # --- destructive GitHub operations ---
    m "${S}gh[[:space:]]+(repo[[:space:]]+(delete|archive|rename|edit)|release[[:space:]]+delete|secret|variable|ssh-key|gpg-key|auth[[:space:]]+(token|logout|refresh|setup-git))" && block "destructive / credential gh command"
    m "${S}gh[[:space:]]+api([[:space:]].*)?(-X|--method)[[:space:]=]*DELETE" && block "gh api DELETE"

    # --- secrets ---
    stripped="${cmd//.env.example/}"
    grep -qE -- "$ENV_RE" <<<"$stripped" && block "command references a .env file"
    grep -qE -- "$ENV_GLOB_RE" <<<"$stripped" && block "glob that may expand to a .env file"
    m "$SECRET_RE"   && block "command references credential files"

    # --- recoverable but risky: require confirmation ---
    m "${S}git[[:space:]]+reset([[:space:]].*)?[[:space:]]--(hard|merge|keep)" && ask "git reset --hard discards local changes"
    m "${S}git[[:space:]]+checkout([[:space:]].*)?[[:space:]](--|\.)([[:space:]]|$)" && ask "git checkout -- / . discards local changes"
    m "${S}git[[:space:]]+restore([[:space:]]|$)" && ask "git restore discards local changes"
    m "${S}git[[:space:]]+stash[[:space:]]+(drop|clear)" && ask "git stash drop/clear"
    emit_ask_or_allow
    ;;

  Read|Edit|Write|NotebookEdit|Grep|Glob)
    for key in file_path notebook_path path; do
      p="$(jq -r ".tool_input.${key} // \"\"" <<<"$input")"
      [[ -z "$p" ]] && continue
      is_env_path "$p"    && block "access to .env file ($p)"
      is_secret_path "$p" && block "access to credential file ($p)"
      if [[ "$tool" == "Edit" || "$tool" == "Write" || "$tool" == "NotebookEdit" ]] && is_protected_path "$p"; then
        block "modifying protected guard / git hook file ($p) — edit it manually"
      fi
    done
    ;;
esac

exit 0
