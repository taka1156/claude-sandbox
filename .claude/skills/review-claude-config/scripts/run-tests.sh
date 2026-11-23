#!/usr/bin/env bash
# Policy test runner for the Claude Code harness (.claude/settings.json + .claude/hooks/guard.sh).
# Computes the effective decision (hook + settings.json permission rules) for each case and
# compares it with the expected policy. Also runs structural checks of the safety baseline.
#
# Usage: run-tests.sh [--root DIR] [--cases FILE]... [--mode auto|default] [--strict] [--quiet]
#   --root     project root containing .claude/ (default: git top level, else current dir)
#   --cases    TSV case file(s) (default: policy-cases.tsv next to this script's skill)
#   --mode     how a Bash command matching no rule is treated:
#              auto    -> OK  (auto mode; the classifier decides, usually no prompt)
#              default -> ASK (default mode prompts for unmatched commands)
#   --strict   also fail on OVER (stops work more than policy); default: OVER is a warning
#   --quiet    print only non-passing cases and the summary
#
# Case format (tab separated): expected  tool  input  [lockfiles]
#   expected  : OK | ASK | BLOCK, or alternatives such as OK/ASK
#   tool      : Bash (input = command) | Read/Edit/Write (input = path)
#   input     : {root} and {home} are replaced with the project root and $HOME
#   lockfiles : comma-separated lockfile names created in a temporary project dir (cwd)
#
# Exit: 0 = no UNDER and baseline checks pass; 1 = UNDER or baseline failure (or OVER with --strict)
#
# Approximations: settings.json is evaluated for Bash rules only (compound commands split on
# && || ; |); Read/Edit/Write cases are judged by the hook only.
set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CASES=()
MODE=auto
STRICT=0
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --cases) CASES+=("$2"); shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --quiet) QUIET=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done
[[ ${#CASES[@]} -gt 0 ]] || CASES=("$SKILL_DIR/policy-cases.tsv")

ROOT="$(cd "$ROOT" && pwd)"
GUARD="$ROOT/.claude/hooks/guard.sh"
SETTINGS="$ROOT/.claude/settings.json"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
for f in "$GUARD" "$SETTINGS" "${CASES[@]}"; do [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 1; }; done
jq empty "$SETTINGS" || { echo "invalid JSON: $SETTINGS" >&2; exit 1; }

annotate() { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::$1::$2"; return 0; }

# ---------- structural baseline checks ----------
base_fail=0
check() {
  if eval "$2"; then
    [[ $QUIET -eq 1 ]] || echo "pass  baseline: $1"
  else
    echo "FAIL  baseline: $1"; annotate error "baseline: $1"; base_fail=$((base_fail+1))
  fi
}
check "disableBypassPermissionsMode is \"disable\"" \
  '[[ "$(jq -r ".permissions.disableBypassPermissionsMode // empty" "$SETTINGS")" == disable ]]'
check "PreToolUse hook runs guard.sh for Bash|Read|Edit|Write|NotebookEdit|Grep|Glob" \
  'jq -e "[.hooks.PreToolUse[]? | select(.hooks[]?.command | test(\"guard\\\\.sh\")) | .matcher | split(\"|\")] | add // [] | (index(\"Bash\") and index(\"Read\") and index(\"Edit\") and index(\"Write\") and index(\"NotebookEdit\") and index(\"Grep\") and index(\"Glob\"))" "$SETTINGS" >/dev/null'
check "hook fails closed on unparsable input" \
  '{ echo "not json" | bash "$GUARD" >/dev/null 2>&1; [[ $? -eq 2 ]]; }'

# ---------- settings.json rule matching ----------
load_rules() {
  jq -r --arg k "$1" '.permissions[$k] // [] | map(select(startswith("Bash("))) | map(sub("^Bash\\("; "") | sub("\\)$"; "")) | join("\n")' "$SETTINGS" | grep -v '^$'
}
mapfile -t DENY  < <(load_rules deny)
mapfile -t ASKR  < <(load_rules ask)
mapfile -t ALLOW < <(load_rules allow)

# Does one simple command match a rule pattern? ("x *" and legacy "x:*" also match bare "x")
match_rule() {
  local s="$1" p="$2"
  p="${p%:\*}"; [[ "$p" != "$2" ]] && p="$p *"
  # shellcheck disable=SC2053
  [[ "$s" == $p ]] && return 0
  [[ "$p" == *" *" && "$s" == "${p% \*}" ]] && return 0
  return 1
}
match_any() { local s="$1"; shift; local r; for r in "$@"; do match_rule "$s" "$r" && return 0; done; return 1; }
split_cmd() { sed -E 's/(\&\&|\|\||;|\|)/\n/g' <<<"$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$'; }

settings_decision() {
  local cmd="$1" part all_allowed=1 any_ask=0
  while IFS= read -r part; do
    match_any "$part" "${DENY[@]}" && { echo deny; return; }
    match_any "$part" "${ASKR[@]}" && any_ask=1
    match_any "$part" "${ALLOW[@]}" || all_allowed=0
  done < <(split_cmd "$cmd")
  [[ $any_ask -eq 1 ]] && { echo ask; return; }
  [[ $all_allowed -eq 1 && ${#ALLOW[@]} -gt 0 ]] && { echo allow; return; }
  echo none
}

# ---------- temporary project dirs with lockfiles ----------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fixture_dir() {
  local key="${1:-none}" d f
  d="$TMP/fx_${key//[^A-Za-z0-9]/_}"
  if [[ ! -d "$d" ]]; then
    mkdir -p "$d"
    if [[ "$key" != none ]]; then
      IFS=',' read -ra files <<<"$key"
      for f in "${files[@]}"; do : > "$d/$f"; done
    fi
  fi
  echo "$d"
}

hook_decision() {
  local tool="$1" input="$2" dir="$3" payload out rc
  if [[ "$tool" == "Bash" ]]; then
    payload="$(jq -n --arg c "$input" --arg d "$dir" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')"
  else
    payload="$(jq -n --arg t "$tool" --arg p "$input" --arg d "$dir" '{tool_name:$t,cwd:$d,tool_input:{file_path:$p}}')"
  fi
  out="$(CLAUDE_PROJECT_DIR="$dir" bash "$GUARD" <<<"$payload" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 2 ]]; then echo BLOCK
  elif [[ "$out" == *'"permissionDecision":"deny"'* || "$out" == *'"permissionDecision": "deny"'* ]]; then echo BLOCK
  elif [[ "$out" == *'"ask"'* ]]; then echo ASK
  else echo OK; fi
}

rank() { case "$1" in OK) echo 0 ;; ASK) echo 1 ;; BLOCK) echo 2 ;; esac; }

# ---------- policy cases ----------
pass=0; over=0; under=0
while IFS=$'\t' read -r exp tool input locks; do
  [[ -z "${exp// /}" || "$exp" == \#* ]] && continue
  input="${input//\{root\}/$ROOT}"; input="${input//\{home\}/$HOME}"
  dir="$(fixture_dir "$locks")"
  h="$(hook_decision "$tool" "$input" "$dir")"
  s="-"
  [[ "$tool" == "Bash" ]] && s="$(settings_decision "$input")"

  if   [[ "$h" == BLOCK || "$s" == deny ]]; then eff=BLOCK
  elif [[ "$h" == ASK   || "$s" == ask  ]]; then eff=ASK
  elif [[ "$s" == allow || "$tool" != "Bash" ]]; then eff=OK
  elif [[ "$MODE" == default ]]; then eff=ASK
  else eff=OK
  fi

  status=pass
  if [[ "/$exp/" != *"/$eff/"* ]]; then
    hi=-1
    IFS='/' read -ra alts <<<"$exp"
    for a in "${alts[@]}"; do r="$(rank "$a")"; (( r > hi )) && hi=$r; done
    if (( $(rank "$eff") > hi )); then status=OVER; else status=UNDER; fi
  fi
  case "$status" in
    pass) pass=$((pass+1)) ;;
    OVER) over=$((over+1)); annotate warning "OVER expected=$exp got=$eff $tool: $input" ;;
    UNDER) under=$((under+1)); annotate error "UNDER expected=$exp got=$eff $tool: $input" ;;
  esac
  if [[ $QUIET -eq 0 || "$status" != pass ]]; then
    printf '%-5s expected=%-9s got=%-5s (hook=%s settings=%s)  %s: %s%s\n' \
      "$status" "$exp" "$eff" "$h" "$s" "$tool" "$input" "${locks:+  [lockfiles=$locks]}"
  fi
done < <(cat "${CASES[@]}")

echo "----"
echo "root=$ROOT mode=$MODE  baseline_fail=$base_fail  pass=$pass  OVER=$over (stops work more than policy)  UNDER=$under (looser than policy)"
(( base_fail == 0 && under == 0 )) || exit 1
(( STRICT == 1 && over > 0 )) && exit 1
exit 0
