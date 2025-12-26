---
title: "コードゼロでGA4分析：MCPでClaudeと直接つないでみた"
emoji: "🔌"
type: "idea" # tech: 技術記事 / idea: アイデア
topics: ["GA4", "Claude", "MCP", "AI", "Webマーケティング"]
published: true
---

:::message
この記事は[茅ヶ崎.rb](https://crb.connpass.com/)の勉強会で学んだ内容をベースにしています。
:::

## はじめに：前回の記事からの進化

[前回の記事](https://zenn.dev/aileron/articles/ga4-analysis-with-claude)では、GA4のデータをClaudeに渡して分析する方法を紹介した。CSVエクスポート、スクリーンショット、APIの3つの方法だ。

しかし、どの方法も「人間がデータを取得してClaudeに渡す」というステップが必要だった。

今回は、その手間すら不要になる方法を紹介する。**MCP（Model Context Protocol）を使えば、Claudeが直接GA4にアクセスして分析できる**。コードを書く必要は一切ない。

## MCPとは何か

MCP（Model Context Protocol）は、Anthropicが開発したオープンプロトコルだ。AIモデルと外部のデータソースやツールを接続するための標準規格である。

```
従来：
人間 → GA4からデータ取得 → Claudeに渡す → 分析結果

MCP：
人間 → Claudeに質問 → Claude が直接GA4にアクセス → 分析結果
```

つまり、「データを取ってきて渡す」という中間作業が完全に不要になる。

## Google Analytics MCPの設定

Claude DesktopにGoogle Analytics MCPを設定する方法を説明する。

### 1. Google Cloud Consoleでの準備

まず、Google Cloud Consoleで認証情報を準備する。

1. [Google Cloud Console](https://console.cloud.google.com/)にアクセス
2. 新しいプロジェクトを作成（または既存のプロジェクトを選択）
3. 「APIとサービス」→「ライブラリ」から「Google Analytics Data API」を有効化
4. 「APIとサービス」→「認証情報」→「認証情報を作成」→「OAuthクライアントID」
5. アプリケーションの種類は「デスクトップアプリ」を選択
6. 作成後、JSONファイルをダウンロード

### 2. Claude Desktopの設定

Claude Desktopの設定ファイルを編集する。

**macOSの場合**：
```bash
code ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

**Windowsの場合**：
```bash
code %APPDATA%\Claude\claude_desktop_config.json
```

設定ファイルに以下を追加：

```json
{
  "mcpServers": {
    "google-analytics": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic/google-analytics-mcp"
      ],
      "env": {
        "GOOGLE_CLIENT_ID": "あなたのクライアントID",
        "GOOGLE_CLIENT_SECRET": "あなたのクライアントシークレット",
        "GA_PROPERTY_ID": "あなたのGA4プロパティID"
      }
    }
  }
}
```

### 3. Claude Desktopを再起動

設定を保存したら、Claude Desktopを再起動する。初回起動時にGoogleアカウントでの認証を求められるので、GA4にアクセス可能なアカウントでログインする。

## 実際に使ってみる

設定が完了すれば、あとは普通にClaudeに話しかけるだけだ。

### 例1：今週のトラフィック概要

```
今週のサイトのトラフィックを分析して。
前週と比較して、どんな変化があるか教えて。
```

Claudeは直接GA4にアクセスし、データを取得して分析してくれる。CSVをエクスポートする必要も、スクリーンショットを撮る必要もない。

### 例2：コンバージョン分析

```
先月のコンバージョン率はどうだった？
コンバージョンに貢献しているチャネルを教えて。
```

### 例3：問題の特定

```
直帰率が高いページを特定して。
改善すべきポイントを3つ提案して。
```

### 例4：定期レポート

```
経営会議向けに、今月のWebサイトパフォーマンスを
1ページにまとめたレポートを作成して。
```

## コードゼロの衝撃

前回の記事では、APIを使った自動化についてPythonのコード例を示した。

```python
# 前回紹介した方法（コードが必要）
from google.analytics.data_v1beta import BetaAnalyticsDataClient
import anthropic

analytics_data = fetch_ga4_data()
client = anthropic.Anthropic()
# ... 以下コードが続く
```

MCPを使えば、このコードは一切不要になる。

```
# 今回の方法（コード不要）
Claudeに「今週のトラフィックを分析して」と話しかけるだけ
```

エンジニアでなくても、Webマーケターが直接Claudeに話しかけてGA4分析ができる。これは大きな変化だ。

## MCPが変えるワークフロー

### Before（従来のワークフロー）

```
月曜朝のルーティン：
1. GA4を開く（2分）
2. 期間を設定（1分）
3. 各種レポートを確認（10分）
4. CSVでエクスポート（3分）
5. Claudeに投げて分析（5分）
6. 結果をまとめる（10分）
合計：約30分
```

### After（MCPを使ったワークフロー）

```
月曜朝のルーティン：
1. Claudeに「先週のサイトパフォーマンスをまとめて」と聞く
2. 結果を確認して、追加の質問があれば聞く
合計：約5分
```

**80%以上の時間削減**。これが、MCPの威力だ。

## 注意点とベストプラクティス

### セキュリティについて

- OAuth認証を使用するため、認証情報は安全に管理される
- GA4の閲覧権限のみが付与される（変更はできない）
- 会社のセキュリティポリシーに従って導入を検討すること

### 精度について

- Claudeは取得したデータを解釈するが、ビジネス固有の文脈は教える必要がある
- 「この数値が高い/低いの基準は？」を明確に伝えると、より適切な分析が得られる
- 重要な意思決定の前には、GA4のUIでも確認することを推奨

### 質問のコツ

```
❌ 曖昧な質問
「サイトの状況を教えて」

✅ 具体的な質問
「先週と今週を比較して、オーガニック検索からの流入に
変化があれば教えて。特に、20%以上変化したページがあれば
リストアップして。」
```

具体的に聞けば、具体的な答えが返ってくる。

## 他のMCPサーバーとの組み合わせ

Google Analytics MCPは単体でも強力だが、他のMCPと組み合わせるとさらに便利になる。

### Google Search Console MCP

```
GA4のトラフィック減少の原因を調べて。
Search Consoleのデータと照らし合わせて、
検索順位の変動があったか確認して。
```

### Slack MCP

```
今週のサイトパフォーマンスをまとめて、
#marketing チャンネルに投稿して。
```

### GitHub MCP

```
直帰率が高いページを特定して、
改善タスクをGitHub Issueとして作成して。
```

AIが複数のツールを横断して作業してくれる。これが、MCPの真の価値だ。

## まとめ

MCPを使ったGA4分析のメリット：

1. **コードゼロ**：エンジニアでなくても直接GA4分析ができる
2. **時間削減**：データ取得の手間が完全に不要
3. **対話的**：追加の質問にもすぐに答えてくれる
4. **拡張性**：他のMCPと組み合わせて、さらに自動化できる

前回の記事で「AIに仕事を奪ってもらう」ことを提案した。MCPは、その「奪ってもらう」のハードルを大幅に下げてくれる。

コードを書ける人だけでなく、すべてのWebマーケターがAIの力を活用できる時代が来た。まずは設定してみてほしい。5分の設定で、毎週30分以上の時間が生まれる。

---

*この記事は茅ヶ崎.rbの勉強会での学びをベースに執筆しました。コミュニティでの学びは、最新のAI活用法をキャッチアップする最良の方法です。*
