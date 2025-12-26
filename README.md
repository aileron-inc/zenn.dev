# zenn.dev

Zenn articles with Hugo static site generation for GitHub Pages.

## Zenn CLI

👇  新しい記事を作成する
$ pnpm zenn new:article

👇  新しい本を作成する
$ pnpm zenn new:book

👇  投稿をプレビューする
$ pnpm zenn preview

## Hugo Setup

👇  Zenn の記事を Hugo 形式に変換
$ ./scripts/convert-to-hugo.sh

👇  Hugo サイトをローカルでプレビュー（draft も含む）
$ cd hugo-site && hugo server -D

👇  Hugo サイトをビルド
$ cd hugo-site && hugo --gc --minify

## GitHub Pages Deploy

1. GitHub リポジトリの Settings > Pages に移動
2. Source を "GitHub Actions" に設定
3. main ブランチに push すると自動的にデプロイされます

ワークフローファイル: `.github/workflows/hugo.yml`
