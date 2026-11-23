#!/usr/bin/env bash
#
# Fetch only the Claude Code harness for the chosen language from sample_harness in
# taka1156/claude-sandbox (dist branch) and place it in the project root.
#
# Placed files (existing files are overwritten only after confirmation; other files are kept):
#   .claude/settings.json, .claude/hooks/guard.sh, .claude/skills/*, .claude/agents/*, CLAUDE.md, AGENTS.md
#
# Usage:
#   ./setup_harness.sh              # pick a language interactively
#   ./setup_harness.sh <language>   # specify the language (e.g. node, python, base)
#
# Run directly via curl (interactive input is read from /dev/tty, so it also
# works when stdin is a pipe):
#   curl -fsSL <raw URL> | bash
#   curl -fsSL <raw URL> | bash -s -- <language>
#
# Environment variables:
#   DEST_DIR  Project root to place the harness in (default: current directory)

set -euo pipefail

REPO_URL="https://github.com/taka1156/claude-sandbox.git"
BRANCH="dist"
BASE_DIR="sample_harness"
DEST_DIR="${DEST_DIR:-.}"

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  { printf '\033[?25h' > /dev/tty; } 2>/dev/null || true  # show the cursor again
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Arrow-key selection menu
#   Usage: select_menu "<prompt>" option1 option2 ...
#   The result is stored in the MENU_RESULT variable.
select_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local count=${#options[@]}
  local selected=0 i key rest

  printf '%s\n' "$prompt" > /dev/tty
  printf '\033[?25l' > /dev/tty  # hide the cursor

  while true; do
    for ((i = 0; i < count; i++)); do
      if [ "$i" -eq "$selected" ]; then
        printf '\033[36m❯ %s\033[0m\033[K\n' "${options[$i]}" > /dev/tty
      else
        printf '  %s\033[K\n' "${options[$i]}" > /dev/tty
      fi
    done

    IFS= read -rsn1 key < /dev/tty || true
    if [ "$key" = $'\033' ]; then
      # arrow keys are 3 bytes: ESC [ A/B
      read -rsn2 -t 0.1 rest < /dev/tty || true
      key+="$rest"
    fi

    case "$key" in
      $'\033[A' | k) selected=$(((selected - 1 + count) % count)) ;;
      $'\033[B' | j) selected=$(((selected + 1) % count)) ;;
      '') break ;;  # Enter
      q | $'\033')
        printf '\033[?25h' > /dev/tty
        echo "Cancelled." >&2
        exit 130
        ;;
    esac

    printf '\033[%dA' "$count" > /dev/tty  # move back to the top of the menu and redraw
  done

  printf '\033[?25h' > /dev/tty
  MENU_RESULT="${options[$selected]}"
}

# Always read interactive input from the terminal (/dev/tty).
if (exec < /dev/tty) 2>/dev/null; then
  TTY_AVAILABLE=1
else
  TTY_AVAILABLE=0
fi

LANG_NAME="${1:-}"
if [ -z "$LANG_NAME" ] && [ "$TTY_AVAILABLE" -eq 0 ]; then
  echo "Error: no terminal (/dev/tty) available; pass the language as an argument." >&2
  exit 1
fi

# --- 1. Fetch only the needed directory (sparse checkout) ---
echo "Fetching harness..."
git clone --quiet --depth 1 --branch "$BRANCH" --filter=blob:none --sparse \
  "$REPO_URL" "$TMP_DIR/repo"
git -C "$TMP_DIR/repo" sparse-checkout set "$BASE_DIR"

SAMPLE_ROOT="$TMP_DIR/repo/$BASE_DIR"
if [ ! -d "$SAMPLE_ROOT" ]; then
  echo "Error: $BASE_DIR not found." >&2
  exit 1
fi

# --- 2. List available variants (subdirectories) ---
LANGS=()
while IFS= read -r d; do
  LANGS+=("$d")
done < <(find "$SAMPLE_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec basename {} \; | sort)

if [ "${#LANGS[@]}" -eq 0 ]; then
  echo "Error: no language directories found." >&2
  exit 1
fi

# --- 3. Decide the language (argument or interactive selection) ---
if [ -z "$LANG_NAME" ]; then
  select_menu "Select a language (↑↓ / j k to move, Enter to confirm, q to cancel):" "${LANGS[@]}"
  LANG_NAME="$MENU_RESULT"
fi

SRC_DIR="$SAMPLE_ROOT/$LANG_NAME"
if [ ! -d "$SRC_DIR" ]; then
  echo "Error: '$LANG_NAME' does not exist." >&2
  echo "Available: ${LANGS[*]}" >&2
  exit 1
fi

# --- 4. Confirm before overwriting existing files ---
mkdir -p "$DEST_DIR"
CONFLICTS=()
while IFS= read -r f; do
  [ -e "$DEST_DIR/$f" ] && CONFLICTS+=("$f")
done < <(cd "$SRC_DIR" && find . -type f | sed 's|^\./||' | sort)

if [ "${#CONFLICTS[@]}" -gt 0 ]; then
  echo "These files already exist in $DEST_DIR and will be overwritten:"
  printf '  %s\n' "${CONFLICTS[@]}"
  if [ "$TTY_AVAILABLE" -eq 0 ]; then
    echo "Aborted (no terminal to confirm)." >&2
    exit 1
  fi
  read -r -p "Overwrite? [y/N]: " ANSWER < /dev/tty
  case "$ANSWER" in
    [yY]*) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# --- 5. Place the files (merge: files not managed by the harness are kept) ---
cp -a "$SRC_DIR/." "$DEST_DIR/"

echo
echo "Done: harness='$LANG_NAME'"
echo "Destination: $(cd "$DEST_DIR" && pwd)"
if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: jq is not installed. The guard hook blocks every Bash command until jq is available." >&2
fi
echo "Verify with: bash .claude/skills/review-claude-config/scripts/run-tests.sh --quiet"
