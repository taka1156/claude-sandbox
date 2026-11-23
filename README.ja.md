<p align="center">
  <img src="logo.png" alt="claude-sandbox logo" width="200">
</p>

# claude-sandbox

[English](README.md)

[Claude Code](https://docs.claude.com/ja/docs/claude-code/overview) をホストマシンから切り離して動かすための、使い捨ての Dev Container／GitHub Codespaces 環境です。

Claude Code はファイルの読み書きやコマンドの実行を行います。コンテナの中で動かせばその影響がホストに及ばないので、安心して作業を任せられ、終わったら環境ごと捨てられます。

## ユースケース

- **ワンショットの実行・検証**: ちょっとしたスクリプトを生成させて、その場で実行して動作を確かめる。ホストの環境を汚さずに、試したら捨てられる。
- **他リポジトリの作業場**: 別のリポジトリをコンテナ内にクローンし、Claude Code に修正させてから元のリポジトリへ push する。GitHub CLI（`gh`）で PR の作成までできる。
- **Claude Code ハーネスの開発・配布**: 権限ルールとガード用の hook を `harness/` で管理し、方針のテストで検証したうえで、言語ごとに生成したセットを自分の他のリポジトリに取り込む（[Claude Code ハーネス](#claude-code-ハーネス)を参照）。

> [!NOTE]
> `git push`、`gh` の書き込み操作（PR の作成やマージなど）、`curl` は、実行前に確認を求める設定にしています。push する前に、Claude Code の変更内容を必ず確認してください。

## 中身

| 項目 | 内容 |
| --- | --- |
| ベースイメージ | `ubuntu:26.04`（LTS） |
| ユーザー | 非 root の `ubuntu`。`sudo` は firewall のスクリプトにだけ許可 |
| ネットワーク | `.devcontainer/init-firewall.sh` で、外部への通信を許可リスト（GitHub、Anthropic、npm レジストリ、VS Code）に制限 |
| 読み取り専用マウント | `.claude/` と `.git/hooks/` はコンテナ内から変更できない |
| Claude Code | 公式のインストールスクリプトで `ubuntu` ユーザーに導入。ログイン情報は名前付きボリュームに保持 |
| Claude Code ハーネス | `.claude/` の権限ルールとガード用の hook（後述） |
| GitHub CLI | Dev Container の `github-cli` feature で導入 |
| ツール | `git`、`git-lfs`、`curl`、`jq`、`ripgrep`、`python3`、`openssh-client`、`zip`／`unzip`／`xz-utils`、`file`、`patch`、`less`、`vim` |
| VS Code 拡張機能 | Claude Code、日本語言語パック、Code Spell Checker、Error Lens |
| ロケール／タイムゾーン | `ja_JP.UTF-8`／`Asia/Tokyo` |

コンテナの設定は [codespacegen](https://github.com/taka1156/codespacegen) で生成しています。

## 使い方

### GitHub Codespaces

1. **Code** → **Codespaces** → **Create codespace on main** をクリックします。
2. コンテナのビルドが終わるまで待ちます。
3. ターミナルを開いて、次を実行します。

   ```sh
   claude
   ```

### VS Code Dev Containers

1. [Docker](https://www.docker.com/) と [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) 拡張機能をインストールします。
2. このリポジトリをクローンして、VS Code で開きます。
3. コマンドパレットから **Dev Containers: Reopen in Container** を実行します。
4. ターミナルを開いて `claude` を実行します。

初回起動時に、Claude アカウントか Anthropic の API キーでのログインを求められます。

## Claude Code ハーネス

ハーネスとは、Claude に何を実行させるかを決める Claude Code の設定一式です。`.claude/settings.json`、ガード用の hook（`.claude/hooks/guard.sh`）、スキル、`CLAUDE.md`、`AGENTS.md` からなります。Dev Container の中で、auto モードで使うことを前提にしています。

| 操作 | 挙動 |
| --- | --- |
| ローカルの git、`gh` の読み取り系、プロジェクトのスクリプト（`pnpm test`、`uv run` など） | 確認なしで実行 |
| `git push`、変更を捨てる git 操作（`reset --hard`、`restore` など）、`gh` の書き込み操作、`curl`／`wget` | 確認を求める |
| ロックファイルに固定された依存の導入（`pnpm install`、`uv sync` など） | 確認を求める |
| 削除、強制 push、履歴の書き換え、秘密情報の読み取り、ハーネスや firewall の変更 | ブロック |
| 依存の追加、`npx`／`dlx` のようなその場限りの実行、グローバルインストール、ロックファイルがない状態での導入 | ブロック |

### 他のリポジトリでハーネスを使う

言語ごとに生成したハーネスを `dist` ブランチで公開しています。取り込み先のリポジトリのルートで次を実行し、言語を選んでください（`base` はパッケージの導入をすべてブロックします）。

```sh
curl -fsSL https://raw.githubusercontent.com/taka1156/claude-sandbox/master/harness/scripts/setup_harness.sh | bash
# 言語を指定する場合: ... | bash -s -- node
```

既存のハーネスのファイルは、確認してから上書きします。それ以外のファイル（`.claude/settings.local.json` など）は残します。取り込んだ結果は、次のコマンドで検証できます。

```sh
bash .claude/skills/review-claude-config/scripts/run-tests.sh --quiet
```

### カスタマイズと生成

| パス | 役割 |
| --- | --- |
| `harness/config.json` | カスタマイズの唯一の入力。`gh` の読み取り系（`allow`／`ask`）、`curl`（`allow`／`ask`）、共同作成者の表記、同梱するスキルとエージェント |
| `harness/lang.json` | 言語ごとのパッケージマネージャー。ロックファイル、ロックファイルどおりに導入するコマンド、依存を追加するコマンド |
| `harness/templates/` | `settings.json`、`guard.sh`、スキル、エージェント、`CLAUDE.md`、`AGENTS.md` のテンプレート |
| `harness/tests/cases/` | 方針のテストケース（安全ラインとカスタマイズ項目）。パッケージのケースは `lang.json` から生成 |
| `harness/scripts/generate.sh` | `sample_harness/<言語>/` と `harness/build/root/` を生成し、すべてのセットをテストする |

`master` で `harness/` が変わると、GitHub Actions がすべてのセットを生成・テストして、`sample_harness/` を `dist` ブランチに強制 push します。方針より緩いテスト結果が出た場合や、ルートが生成物とずれている場合は、実行が失敗します。

### このリポジトリ自身のハーネスを更新する

このリポジトリは、`base` のセットに `sync-readme` エージェントを加えたものを使っています。コンテナ内では `.claude/` が読み取り専用なので、ホスト側で更新します。

```sh
bash harness/scripts/generate.sh
cp -R harness/build/root/. .
```

生成されなくなったファイルを削除してから、push する前に `bash harness/scripts/generate.sh --check-root` が通ることを確認してください。

## 注意点

- コンテナはホストから切り離され、外部への通信も制限されていますが、ワークスペース内のファイルはすべて見えます。読まれたくない秘密情報はワークスペースに置かないでください。
- コンテナを作り直すと、中での変更は消えます。残したいものはコミットしてプッシュしてください。
- サンドボックスの中であっても、Claude Code の変更はプッシュする前に確認してください。

## ライセンス

[MIT](LICENSE)
