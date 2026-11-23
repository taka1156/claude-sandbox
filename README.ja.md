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

> [!NOTE]
> `git push` と `gh pr create` は、実行前に確認を求める設定にしています。push する前に、Claude Code の変更内容を必ず確認してください。

## 中身

| 項目 | 内容 |
| --- | --- |
| ベースイメージ | `ubuntu:26.04`（LTS） |
| Claude Code | 公式のインストールスクリプトで導入し、`/usr/local/bin/claude` にリンク |
| GitHub CLI | Dev Container の `github-cli` feature で導入 |
| ツール | `git`、`git-lfs`、`curl`、`jq`、`ripgrep`、`python3`、`openssh-client`、`zip`／`unzip`／`xz-utils`、`file`、`patch`、`less`、`vim` |
| VS Code 拡張機能 | Claude Code、日本語言語パック、Code Spell Checker、Error Lens |
| ロケール／タイムゾーン | `ja_JP.UTF-8`／`Asia/Tokyo` |

設定は [codespacegen](https://github.com/taka1156/codespacegen) で生成しています。

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

## 注意点

- コンテナはホストから切り離されていますが、ネットワークには接続でき、ワークスペース内のファイルはすべて見えます。読まれたくない秘密情報はワークスペースに置かないでください。
- コンテナを作り直すと、中での変更は消えます。残したいものはコミットしてプッシュしてください。
- サンドボックスの中であっても、Claude Code の変更はプッシュする前に確認してください。

## ライセンス

[MIT](LICENSE)