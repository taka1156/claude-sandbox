---
name: review-claude-config
description: Review this repo's Claude Code safety setup (.claude/settings.json, .claude/hooks/guard.sh, .devcontainer/*) on the premise that Claude runs inside the dev container. Verifies it is secure without blocking routine work, runs the bundled policy test suite, classifies findings, and applies approved fixes. Use when asked to review, audit or verify the Claude config, permissions, guard hook or dev container security.
---

# Review Claude Code config (dev container premise)

Goal: judge whether the setup is **secure enough without stopping routine work**, and whether each gap is an **acceptable compromise**. Always use the criteria below; do not invent new review angles per run.

## Premise

- Claude runs **inside the dev container** defined in `.devcontainer/` (non-root `ubuntu`, egress allowlist firewall, `.claude/` and `.git/hooks/` mounted read-only).
- The container is the primary boundary. `guard.sh` and permission rules are a second layer (best-effort regex).
- Do NOT recommend Claude Code's bwrap `sandbox`; it conflicts with Docker's default seccomp and was rejected.

## Threat model (all four, nothing else)

1. **Accidental destruction**: deletes, history rewrite, force push, discarding work.
2. **Prompt injection**: instructions embedded in web pages, packages or issues leading to secret exfiltration or outbound data transfer.
3. **Supply chain**: malicious packages / install scripts executed in the container.
4. **Guard tampering**: Claude modifying or bypassing settings, hooks, firewall or git hooks.

## Decision policy (expected behavior)

| Category | Expected |
|---|---|
| Local git: `status`, `diff`, `log`, `add`, `commit`, `switch` | allow (no prompt) |
| `git checkout -b` (side effect of a broad `git checkout *` ask rule; `git switch -c` is the no-prompt path) | allow or ask |
| `gh` read-only: `pr/issue/run/repo view`, `list`, `status`, `diff`, `checks` | allow |
| `gh` writes: `pr create/merge/comment`, `issue create`, `gh api` non-DELETE | ask |
| `gh` destructive / credentials: `repo delete`, `release delete`, `auth token`, `secret`, `api -X DELETE` | block |
| `curl` / `wget` plain requests (firewall limits destinations, but allowlisted hosts can still receive exfiltrated data) | allow or ask |
| Remote script execution: `curl … \| sh`, `bash <(curl …)` | block |
| Packages, **any language** (not tied to one manager): install exactly what the project's lockfile pins, with the matching lockfile present (`pnpm install`, `npm ci`, `uv sync`, `bundle install`, `go mod download`…) | ask |
| Packages: same install command but the matching lockfile is absent | block |
| Packages: adding deps (`add`, `require`, `go get`, `npm install <pkg>`, `pip install <pkg>`) | block |
| Packages: one-shot remote execution (`npx`, `dlx`, `npm exec`, `bunx`, `uvx`, `pipx run`, `go run pkg@ver`) | block |
| Packages: global / system install (`-g`, `cargo/go/gem/pipx install`, `uv tool install`, `apt`, `brew`) | block |
| Project scripts that use installed deps (`pnpm test`, `uv run`, `cargo build`, `bundle exec`) | allow |
| `git push` (normal) | ask |
| Recoverable-but-lossy git: `reset --hard`, `checkout -- .`, `restore`, `stash drop/clear` | ask |
| Irreversible: `rm`, `find -delete`, script-language deletes, `git clean/rm`, `branch -D`, force/delete push, history rewrite | block |
| Secrets: `.env*` (except `.env.example`), gh token, SSH keys, Claude credentials | block |
| Guard tampering: edit `.claude/settings*.json`, `.claude/hooks/`, `.git/hooks/`, `.git/config` exec keys | block |
| Ordinary dev commands that merely *look* risky (regex like `.{0,3}` or `.*`, the word `rm` in a message) | allow (false positive = over-blocking) |

"allow or ask" means both outcomes pass (`OK/ASK` in the TSV); do not report either as a finding.
`policy-cases.tsv` encodes this table. When the policy changes, update the table and the TSV together.

## Steps

1. **Read** `.claude/settings.json`, `.claude/hooks/guard.sh`, `.devcontainer/{Dockerfile,docker-compose.yaml,devcontainer.json,init-firewall.sh}`. Use the Read tool for `.claude/` files (the guard blocks Bash commands that reference them).
2. **Run the policy tests**:
   ```
   bash .claude/skills/review-claude-config/scripts/run-tests.sh
   ```
   Options: `--mode default|auto` (how unmatched Bash commands are treated; default `auto`), `--guard <path>` / `--settings <path>` to test a proposed version.
   Output lines: `pass` / `OVER` (stops work more than policy) / `UNDER` (looser than policy).
   Package cases run against `fixtures/<name>/` (empty lockfiles) as project dir and cwd; add a fixture when a case needs a different lockfile set.
3. **Static checklist** (things tests cannot see):
   - Container: runs as non-root; sudoers allows only `init-firewall.sh`; user not in `sudo` group; only `NET_ADMIN`/`NET_RAW` added; no host secrets or docker socket mounted.
   - Firewall: resolves before flushing; DROP policy set first; IPv6 dropped; verification step fails the start; allowlist contains only needed domains.
   - Read-only mounts cover `.claude` and `.git/hooks`.
   - Settings: `disableBypassPermissionsMode: "disable"`; no broad `allow` that overrides the policy; no `attribution` lines reintroduced; hook matcher covers `Bash|Read|Edit|Write|NotebookEdit|Grep|Glob`.
   - Hook: fails closed on parse error; jq-missing fallback blocks Bash; timeout reasonable.
4. **Classify** every finding:
   - **要修正**: UNDER for a threat in the model, or OVER that blocks a policy "allow" item in daily work.
   - **妥協可**: a gap that is listed under accepted trade-offs, or needs an unlikely multi-step bypass and is covered by another layer. State which layer covers it.
   - **問題なし**: matches policy.
5. **Report** (in Japanese, per AGENTS.md): Conclusion → test summary (pass / OVER / UNDER counts) → findings table `| 分類 | 観点 | 内容 | 根拠 | 修正案 |` → next action. Every finding cites the test line or file:line.
6. **Fix** only after the user approves specific findings:
   - `.devcontainer/*`: edit directly.
   - `.claude/*` (read-only in the container, guarded): write the proposed full file to the scratchpad, re-run tests with `--guard` / `--settings` pointing at it, then show the **full file content** for the user to copy-paste on the host.
   - After applying, re-run the tests and report the new counts.

## Accepted trade-offs (do not re-raise unless the setup changed)

- gh token is readable by the same OS user; mitigated by hook/deny rules and GitHub-side fine-grained PAT + branch protection.
- Regex guards are bypassable in principle; the container boundary covers residual risk.
- IP-based firewall allowlist can drift with CDN IP changes; re-run `sudo /usr/local/bin/init-firewall.sh`.
- `.claude/` read-only means "always allow" choices are not persisted.
- `.env` inside the repo is protected only by hook/deny rules, not by mounts.
- Allowlisted domains (e.g. GitHub) can still be used as an exfiltration channel; accepted for usability.
- Lockfiles are looked up only in the hook's `cwd` and the project root; installs in a monorepo subdirectory (`cd app && pnpm install`) are blocked and must be run manually.
- Build/test commands that fetch deps implicitly (`cargo build`, `uv run`) are allowed; lockfile pins and the firewall cover them.
- Package policy lives in `guard.sh` only; do not re-add install rules to `settings.json` deny/ask (a deny there would override the lockfile "ask").

## Out of scope

Application code, CI, GitHub repository settings (mention only as recommendations).
