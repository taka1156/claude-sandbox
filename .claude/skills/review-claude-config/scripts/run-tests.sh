#!/usr/bin/env bash
# Policy test runner for the Claude Code guard setup.
# Computes the effective decision (hook + settings.json permission rules) for each case in
# policy-cases.tsv and compares it with the expected policy.
#
# Usage: run-tests.sh [--mode auto|default] [--guard PATH] [--settings PATH] [--cases PATH] [--quiet]
#   --mode     how a Bash command matching no rule is treated:
#              auto    -> OK  (auto mode; classifier decides, usually no prompt)
#              default -> ASK (default mode prompts for unmatched commands)
#   --quiet    print only non-passing cases and the summary
#
# Approximations (keep in mind when reading results):
#   - settings.json is evaluated for Bash rules only; compound commands are split on && || ; |
#   - Read/Edit/Write cases are judged by the hook only
set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
GUARD="$ROOT/.claude/hooks/guard.sh"
SETTINGS="$ROOT/.claude/settings.json"
CASES="$SKILL_DIR/policy-cases.tsv"
MODE=auto
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --guard) GUARD="$2"; shift 2 ;;
    --settings) SETTINGS="$2"; shift 2 ;;
    --cases) CASES="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
for f in "$GUARD" "$SETTINGS" "$CASES"; do [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 1; }; done
jq empty "$SETTINGS" || { echo "invalid JSON: $SETTINGS" >&2; exit 1; }

# Load Bash(...) patterns of a permission list
load_rules() {
  jq -r --arg k "$1" '.permissions[$k] // [] | .[] | select(startswith("Bash(")) | sub("^Bash\\("; "") | sub("\\)$"; "")' "$SETTINGS"
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

pass=0; over=0; under=0
while IFS=$'\t' read -r exp tool input fixture; do
  [[ -z "${exp// /}" || "$exp" == \#* ]] && continue
  dir="$SKILL_DIR/fixtures/${fixture:-none}"
  [[ -d "$dir" ]] || { echo "missing fixture: $dir" >&2; exit 1; }
  h="$(hook_decision "$tool" "$input" "$dir")"
  s="-"
  if [[ "$tool" == "Bash" ]]; then s="$(settings_decision "$input")"; fi

  if   [[ "$h" == BLOCK || "$s" == deny ]]; then eff=BLOCK
  elif [[ "$h" == ASK   || "$s" == ask  ]]; then eff=ASK
  elif [[ "$s" == allow || "$tool" != "Bash" ]]; then eff=OK
  else [[ "$MODE" == default ]] && eff=ASK || eff=OK
  fi

  status=pass
  if [[ "/$exp/" != *"/$eff/"* ]]; then
    lo=9; hi=-1
    IFS='/' read -ra alts <<<"$exp"
    for a in "${alts[@]}"; do r="$(rank "$a")"; (( r < lo )) && lo=$r; (( r > hi )) && hi=$r; done
    if (( $(rank "$eff") > hi )); then status=OVER; else status=UNDER; fi
  fi
  case "$status" in pass) pass=$((pass+1)) ;; OVER) over=$((over+1)) ;; UNDER) under=$((under+1)) ;; esac
  if [[ $QUIET -eq 0 || "$status" != pass ]]; then
    printf '%-5s expected=%-9s got=%-5s (hook=%s settings=%s)  %s: %s%s\n' "$status" "$exp" "$eff" "$h" "$s" "$tool" "$input" "${fixture:+  [fixture=$fixture]}"
  fi
done < "$CASES"

echo "----"
echo "mode=$MODE  pass=$pass  OVER=$over (stops work more than policy)  UNDER=$under (looser than policy)"
[[ $over -eq 0 && $under -eq 0 ]]
