# CLAUDE.md - Zenn.dev Repository

## 概要
このリポジトリは、vnovelプロジェクトからエピソードをZenn.devのブック形式でインポートして公開するためのものです。

## インポートルール

### 重要な制約
- **エピソードファイルのみをインポートする**
- 設定系のmarkdownファイル（setting.md、WORLDBOOK.md、claude.mdなど）はインポートしない
- prompts/ディレクトリ内のファイルもインポートしない
- episodes/ディレクトリ内のファイルのみを対象とする

### インポート手順

1. ソースプロジェクトからエピソードファイルを特定
   ```bash
   ls /Users/aileron/Workspace/vnovel/projects/[project-name]/episodes/*.md
   ```

2. Zenn.devのブック構造に従ってディレクトリを作成
   ```bash
   mkdir -p /Users/aileron/Workspace/zenn.dev/books/[book-slug]
   ```

3. エピソードファイルのみをコピー
   ```bash
   cp /Users/aileron/Workspace/vnovel/projects/[project-name]/episodes/*.md \
      /Users/aileron/Workspace/zenn.dev/books/[book-slug]/
   ```

4. config.yamlを作成してチャプター構成を定義

## 現在インポート済みのプロジェクト

### 1. sengoku-artillery (戦国砲術師)
- ソース: `/Users/aileron/Workspace/vnovel/projects/sengoku-artillery`
- ブック: `/Users/aileron/Workspace/zenn.dev/books/sengoku-artillery`
- エピソード数: 11章（episode_00 〜 episode_10）

## Zennブック構造
```
books/
└── [book-slug]/
    ├── config.yaml          # ブックの設定
    ├── cover.png           # カバー画像（オプション）
    └── [chapter-slug].md   # 各チャプター（エピソードファイル）
```

## config.yaml の必須項目
- title: ブックのタイトル
- summary: ブックの概要
- topics: トピック（配列）
- published: 公開状態（true/false）
- chapters: チャプターの順序（配列）

## 注意事項
- エピソードファイル以外の設定ファイルは機密情報や世界観設定を含む可能性があるため、公開リポジトリにはコピーしない
- 各エピソードファイルは独立して読めるように書かれていることを前提とする