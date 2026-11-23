# claude-sandbox

[日本語](README.ja.md)

A disposable Dev Container / GitHub Codespaces environment for running [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) isolated from your host machine.

Claude Code can read, write and run commands on your files. Running it inside a container keeps those changes away from your host, so you can let it work more freely and throw the environment away when you're done.

## What's inside

| Item | Details |
| --- | --- |
| Base image | `ubuntu:26.04` (LTS) |
| Claude Code | Installed with the official install script and linked to `/usr/local/bin/claude` |
| VS Code extensions | Claude Code, Japanese Language Pack, Code Spell Checker, Error Lens |
| Locale / time zone | `ja_JP.UTF-8` / `Asia/Tokyo` |

The configuration is generated with [codespacegen](https://github.com/taka1156/codespacegen).

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

## Notes

- The container separates Claude Code from your host, but it still has network access and can see everything in the workspace. Don't put secrets you don't want it to read in the workspace.
- Changes made inside the container are lost when it is rebuilt. Commit and push anything you want to keep.
- Even in a sandbox, review what Claude Code does before you push its changes.

## License

[MIT](LICENSE)