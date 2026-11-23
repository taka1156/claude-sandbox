<p align="center">
  <img src="logo.png" alt="claude-sandbox logo" width="200">
</p>

# claude-sandbox

[日本語](README.ja.md)

A disposable Dev Container / GitHub Codespaces environment for running [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) isolated from your host machine.

Claude Code can read, write and run commands on your files. Running it inside a container keeps those changes away from your host, so you can let it work more freely and throw the environment away when you're done.

## Use cases

- **One-shot runs and quick checks**: Have Claude Code generate a small script, run it, and check the result on the spot. Your host environment stays clean, and you can throw the container away afterwards.
- **Workbench for other repositories**: Clone another repository into the container, let Claude Code make changes, and push them back to the original repository. The GitHub CLI (`gh`) also lets you open a pull request from here.
- **Develop and distribute a Claude Code harness**: Maintain the permission rules and guard hook in `harness/`, verify them with the policy tests, and install the generated set for each language into your other repositories (see [Claude Code harness](#claude-code-harness)).

> [!NOTE]
> `git push`, `gh` write operations (creating or merging pull requests, etc.) and `curl` ask for confirmation before they run. Always review Claude Code's changes before pushing.

## What's inside

| Item | Details |
| --- | --- |
| Base image | `ubuntu:26.04` (LTS) |
| User | Non-root `ubuntu`; `sudo` is allowed only for the firewall script |
| Network | Outbound traffic is limited to an allowlist (GitHub, Anthropic, npm registry, VS Code) by `.devcontainer/init-firewall.sh` |
| Read-only mounts | `.claude/` and `.git/hooks/` cannot be changed from inside the container |
| Claude Code | Installed with the official install script for the `ubuntu` user; sign-in is kept in a named volume |
| Claude Code harness | Permission rules and a guard hook in `.claude/` (see below) |
| GitHub CLI | Added with the `github-cli` Dev Container feature |
| Tools | `git`, `git-lfs`, `curl`, `jq`, `ripgrep`, `python3`, `openssh-client`, `zip` / `unzip` / `xz-utils`, `file`, `patch`, `less`, `vim` |
| VS Code extensions | Claude Code, Japanese Language Pack, Code Spell Checker, Error Lens |
| Locale / time zone | `ja_JP.UTF-8` / `Asia/Tokyo` |

The container configuration is generated with [codespacegen](https://github.com/taka1156/codespacegen).

## Getting started

### GitHub Codespaces

1. Click **Code** → **Codespaces** → **Create codespace on main**.
2. Wait for the container to build.
3. Open a terminal and run:

   ```sh
   claude
   ```

### VS Code Dev Containers

1. Install [Docker](https://www.docker.com/) and the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension.
2. Clone this repository and open it in VS Code.
3. Run **Dev Containers: Reopen in Container** from the command palette.
4. Open a terminal and run `claude`.

On first launch, Claude Code asks you to sign in with your Claude account or an Anthropic API key.

## Claude Code harness

The harness is the set of Claude Code settings that decides what Claude may run: `.claude/settings.json`, the guard hook `.claude/hooks/guard.sh`, skills, `CLAUDE.md` and `AGENTS.md`. It assumes it runs inside a dev container in auto mode.

| Operation | Behavior |
| --- | --- |
| Local git, `gh` read-only, project scripts (`pnpm test`, `uv run`, …) | Runs without asking |
| `git push`, lossy git (`reset --hard`, `restore`, …), `gh` writes, `curl` / `wget` | Asks for confirmation |
| Installing what the project's lockfile pins (`pnpm install`, `uv sync`, …) | Asks for confirmation |
| Deletes, force push, history rewrite, reading secrets, changing the harness or firewall | Blocked |
| Adding dependencies, `npx` / `dlx` style one-shot runs, global installs, installs without a lockfile | Blocked |

### Use the harness in another repository

The generated harness for each language is published on the `dist` branch. Run this in the root of the target repository and pick a language (`base` blocks every package install):

```sh
curl -fsSL https://raw.githubusercontent.com/taka1156/claude-sandbox/master/harness/scripts/setup_harness.sh | bash
# or specify the language: ... | bash -s -- node
```

Existing harness files are overwritten only after confirmation; other files (such as `.claude/settings.local.json`) are kept. Verify the result with:

```sh
bash .claude/skills/review-claude-config/scripts/run-tests.sh --quiet
```

### Customize and generate

| Path | Role |
| --- | --- |
| `harness/config.json` | The only customization input: `gh` read-only (`allow` / `ask`), `curl` (`allow` / `ask`), co-author attribution, bundled skills and agents, and repository-only extras (`root`) |
| `harness/lang.json` | Package managers per language: lockfiles, lockfile install commands, add commands |
| `harness/templates/` | Templates for `settings.json`, `guard.sh`, skills, agents, `CLAUDE.md`, `AGENTS.md` |
| `harness/tests/cases/` | Policy test cases (the safety baseline and options); package cases are generated from `lang.json` |
| `harness/scripts/generate.sh` | Generates `sample_harness/<language>/` and `harness/build/root/`, then tests every set |

When `harness/` changes on `master`, GitHub Actions generates and tests all sets and force-pushes `sample_harness/` to the `dist` branch. A test that is looser than the policy, or a root that differs from the generated one, fails the run.

### Update this repository's own harness

This repository uses the `base` set plus repository-only extras: the `develop-harness` skill (project overview, requirements and change procedure for the generator) and the `sync-readme` agent. Because `.claude/` is read-only inside the container, update it on the host:

```sh
bash harness/scripts/generate.sh
cp -R harness/build/root/. .
```

Remove files that are no longer generated, then confirm `bash harness/scripts/generate.sh --check-root` passes before pushing.

## Notes

- The container separates Claude Code from your host and limits outbound traffic, but it can still see everything in the workspace. Don't put secrets you don't want it to read in the workspace.
- Changes made inside the container are lost when it is rebuilt. Commit and push anything you want to keep.
- Even in a sandbox, review what Claude Code does before you push its changes.

## License

[MIT](LICENSE)
