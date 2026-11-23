---
name: review-claude-config
description: Review this repo's Claude Code harness (.claude/settings.json and .claude/hooks/guard.sh) on the premise that Claude runs inside a dev container in auto mode. Verifies it stops dangerous operations without blocking routine work, runs the bundled policy test suite, classifies findings, and fixes approved ones. Use when asked to review, audit or verify the Claude config, permissions or guard hook.
---

# Review the Claude Code harness

Judge whether the harness is **secure enough without stopping routine work**, and whether each gap is an **acceptable compromise**. Use only the criteria below; do not invent new review angles per run.

## Premise

- Claude runs **inside a dev container** in **auto mode**. Unmatched commands are left to the auto-mode classifier and count as "no prompt" in tests (real behavior may occasionally prompt).
- Trust model: the operator works only on their own assets or official, trusted sources. Third-party code is run only in a container that may be thrown away.

## Threat model (exactly these four)

1. **Accidental destruction**: deletes, history rewrite, force push, discarding work.
2. **Prompt injection**: instructions in web pages, packages or issues leading to secret exfiltration.
3. **Supply chain**: packages / install scripts executed in the container.
4. **Guard tampering**: Claude modifying or bypassing the settings, hook, git hooks or the container firewall.

## Out of scope (operator responsibility — never report)

- Settings, `CLAUDE.md` or skills brought in by repositories the operator chose to work on.
- Misuse of legitimate credentials (token scopes, branch protection are managed on GitHub).
- The container itself: user (root is fine), firewall, mounts. If the operator removes them, that is their call.
- Languages not defined in `lang.json` (their package managers are not recognized by the hook).

## Layer responsibilities

| Layer | Owns |
|---|---|
| `settings.json` | Static prefix rules: `deny` for irreversible ops, `ask` for confirmation |
| `guard.sh` | Context-dependent decisions: lockfile checks, bypass detection (`/bin/rm`, `\rm`, script deletes, compound commands), reasons for ask, blocking firewall / privilege commands |
| Container | Outer boundary (premise only, not reviewed) |
| `CLAUDE.md` / `AGENTS.md` / skills | Working conventions. **Never count as a security control** |

Duplication rule: irreversible operations (delete, force push, secret reads, guard tampering) are blocked in **both** settings and hook. Everything else lives in **one** layer only. Report violations either way.

## Safety baseline (must always hold)

1. Irreversible operations blocked (settings + hook).
2. Secret reads blocked (`.env*` except `.env.example`, gh token, SSH keys, Claude credentials).
3. Guard tampering blocked (settings, hooks, `.git/hooks`, exec-capable git config, `sudo` / `iptables` / `ipset` / `nft`).
4. Hook fails closed on unparsable input.
5. `disableBypassPermissionsMode: "disable"`.

## Decision policy

| Category | Expected |
|---|---|
| Local git (`status`, `diff`, `log`, `add`, `commit`, `switch`) | allow |
| `git checkout -b` | allow or ask |
| `git push` (normal); lossy git (`reset --hard`, `checkout -- .`, `restore`, `stash drop/clear`) | ask |
| `gh` read-only | per config `gh_read` (default allow) |
| `gh` writes (`pr create/merge/comment`, `issue create`, `api`…) | ask |
| `gh` destructive / credentials (`repo delete`, `* delete`, `auth token`, `secret`) | block |
| `curl` / `wget` plain requests | per config `curl` (default ask) |
| Remote script execution (`curl … \| sh`, `bash <(curl …)`) | block |
| Packages: lockfile install with the matching lockfile, enabled language | ask |
| Packages: lockfile missing, language not enabled, adding deps, one-shot (`npx`, `dlx`, `uvx`…), global / system install | block |
| Project scripts (`pnpm test`, `uv run`, `cargo build`) | allow |
| Look-alikes: regex such as `.{0,3}` / `.*` / `.[]` in quotes, words like `rm` inside commit messages | allow (false positive = OVER) |

"allow or ask" means both outcomes pass (`OK/ASK` in the cases); never report either as a finding.

## Steps

1. **Read** `.claude/settings.json` and `.claude/hooks/guard.sh` with the Read tool (the hook blocks Bash commands that mention these paths).
2. **Run the tests**:
   ```
   bash .claude/skills/review-claude-config/scripts/run-tests.sh --quiet
   ```
   Cases are in `policy-cases.tsv` next to this file (generated). Output: `pass` / `OVER` (stops work more than policy) / `UNDER` (looser than policy) plus baseline checks.
3. **Static review** of what tests cannot see: layer responsibilities and the duplication rule; rules in `settings.json` that contradict the hook (e.g. a `deny` overriding a hook `ask`); new tools or commands that fall outside every rule.
4. **Classify** each finding:
   - **要修正**: any UNDER or baseline failure; an OVER that blocks a policy "allow" item in daily work; a duplication-rule violation.
   - **妥協可**: listed under accepted trade-offs below, or needs an unlikely multi-step bypass covered by the container. Name the covering layer.
   - **問題なし**: matches policy (report the count only).
5. **Report** in Japanese: Conclusion → test summary (baseline / pass / OVER / UNDER counts) → findings table `| 分類 | 観点 | 内容 | 根拠 | 修正案 |` (every finding cites a test line or file:line) → next action.
6. **Fix** only findings the user approves:
   - If the repository contains `harness/` (the generator): edit `harness/templates/`, `harness/tests/cases/`, `harness/config.json` or `harness/lang.json`, run `bash harness/scripts/generate.sh`, and have the user copy `harness/build/root/` to the root on the host (`.claude/` is protected).
   - Otherwise the harness was installed from the `dist` branch: report the fix as a change for the upstream generator; local edits to `.claude/` are the operator's call.

## Accepted trade-offs (do not re-raise unless the setup changed)

- Regex guards are bypassable in principle; the container is the outer boundary.
- Allowlisted domains can still receive exfiltrated data; `curl` asks by default.
- Lockfiles are looked up only in the hook's `cwd` and the project root; installs in a monorepo subdirectory are blocked and must be run manually.
- Build/test commands that fetch deps implicitly (`cargo build`, `uv run`) are allowed; lockfile pins and the firewall cover them.
- `yarn --version` / `bundle --version`-style calls look like lockfile installs and may ask or block.
- `gh api` asks even for read-only calls (prefix rules cannot tell GET from POST).
- Bash commands that merely mention `.claude/settings.json` or `.claude/hooks` (including generated copies) are blocked; use the Read tool.
