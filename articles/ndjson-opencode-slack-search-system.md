---
title: "NDJSON + OpenCode + Slack Bot：RAGを使わないシンプル検索システム"
emoji: "🔍"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["NDJSON", "OpenCode", "Slack", "Bot", "検索"]
published: true
---

## はじめに

RAG（Retrieval-Augmented Generation）は強力だ。ベクトル検索で関連ドキュメントを取得し、LLMに渡す。しかし、すべてのユースケースにRAGが必要だろうか？

実は、多くのケースで**もっとシンプルな方法**が有効だ。

```
RAGアーキテクチャ:
ドキュメント → Embedding → ベクトルDB → 類似検索 → LLM → 回答

シンプルアーキテクチャ:
NDJSON → grep/テキスト検索 → LLM → 回答
```

この記事では、NDJSON + OpenCode + Slack Bot (Socket Mode) を組み合わせた、**RAGを使わないシンプルな検索システム**を紹介する。

## なぜRAGを使わないのか

RAGには以下のコストがかかる：

- **Embedding生成コスト**：ドキュメントをベクトル化するAPI呼び出し
- **ベクトルDB運用コスト**：Pinecone、Weaviate、pgvectorなどの管理
- **複雑性**：チャンク分割、埋め込みモデル選定、検索パラメータ調整

一方、以下のようなケースではRAGは過剰だ：

- ドキュメント数が数千件以下
- 構造化されたデータ（JSON）を扱う
- キーワード検索で十分な精度が出る
- リアルタイム更新が必要

そこで登場するのが**NDJSON**だ。

## NDJSONとは

NDJSON（Newline Delimited JSON）は、1行1JSONオブジェクトの形式だ。

```ndjson
{"id": 1, "title": "Railsの始め方", "content": "Railsは..."}
{"id": 2, "title": "Dockerの基礎", "content": "Dockerは..."}
{"id": 3, "title": "AWSの設定", "content": "AWSの..."}
```

### NDJSONの利点

1. **追記が簡単**：ファイル末尾に1行追加するだけ
2. **ストリーミング処理**：1行ずつ読み込める
3. **grep互換**：普通のテキストツールで検索可能
4. **Git管理しやすい**：差分が行単位で見える
5. **データベース不要**：ファイルだけで完結

```bash
# "Rails" を含む行を検索
grep "Rails" knowledge.ndjson

# jqでフィルタリング
cat knowledge.ndjson | jq -c 'select(.category == "技術")'
```

## システム構成

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│  Slack Bot  │ ──→  │   OpenCode   │ ──→  │    LLM      │
│(Socket Mode)│      │   Server     │      │(Claude/Grok)│
└─────────────┘      └──────────────┘      └─────────────┘
       ↓                    ↓
       │             ┌──────────────┐
       └────────────→│   NDJSON     │
                     │   データ     │
                     └──────────────┘
```

- **Slack Bot (Socket Mode)**：ユーザーからの問い合わせを受け付け
- **NDJSON**：ナレッジベース（検索対象データ）
- **OpenCode Server**：LLMとの通信を抽象化
- **LLM**：検索結果をもとに回答生成

## Slack Bot (Socket Mode) とは

Slack Botには2つの接続方式がある：

| 方式 | 特徴 |
|------|------|
| HTTP (Webhook) | 公開URLが必要、HTTPリクエストを受信 |
| **Socket Mode** | WebSocket接続、ファイアウォール内でも動作 |

Socket Modeは**WebSocketで常時接続**するため：

- 公開URLが不要（ローカル開発に最適）
- NATやファイアウォールを気にしなくていい
- レイテンシが低い

```bash
# 必要な環境変数
SLACK_BOT_TOKEN=xoxb-xxxxx     # Bot Token
SLACK_APP_TOKEN=xapp-xxxxx     # App-Level Token（Socket Mode用）
```

## 実装

### 1. NDJSONナレッジベースの作成

まず、検索対象のデータをNDJSON形式で用意する。

```ndjson
{"id": "doc-001", "title": "新規プロジェクトの立ち上げ手順", "category": "プロセス", "content": "1. リポジトリ作成 2. 開発環境構築 3. CI/CD設定...", "tags": ["プロジェクト", "開発環境"]}
{"id": "doc-002", "title": "本番デプロイ手順", "category": "運用", "content": "1. PRレビュー 2. マージ 3. デプロイ承認...", "tags": ["デプロイ", "本番"]}
{"id": "doc-003", "title": "障害対応フロー", "category": "運用", "content": "1. 検知 2. 影響範囲特定 3. 復旧作業...", "tags": ["障害", "インシデント"]}
```

新しいナレッジの追加は1行追記するだけ：

```bash
echo '{"id": "doc-004", "title": "新しいドキュメント", ...}' >> knowledge.ndjson
```

### 2. 検索モジュール

NDJSONを検索するRubyモジュール：

```ruby
# lib/ndjson_search.rb
module NdjsonSearch
  class << self
    def search(file_path, query, limit: 5)
      results = []

      File.foreach(file_path) do |line|
        doc = JSON.parse(line)
        score = calculate_score(doc, query)
        results << { doc: doc, score: score } if score > 0
      end

      results
        .sort_by { |r| -r[:score] }
        .first(limit)
        .map { |r| r[:doc] }
    end

    private

    def calculate_score(doc, query)
      score = 0
      query_terms = query.downcase.split(/\s+/)

      # タイトルマッチは重み付け高め
      query_terms.each do |term|
        score += 3 if doc['title']&.downcase&.include?(term)
        score += 2 if doc['tags']&.any? { |t| t.downcase.include?(term) }
        score += 1 if doc['content']&.downcase&.include?(term)
      end

      score
    end
  end
end
```

### 3. Slack Bot (Socket Mode)

```ruby
# slack_bot.rb
require 'slack-ruby-client'
require 'json'
require_relative 'lib/ndjson_search'
require_relative 'lib/opencode_client'

Slack.configure do |config|
  config.token = ENV['SLACK_BOT_TOKEN']
end

# Socket Mode クライアント
client = Slack::RealTime::Client.new

client.on :message do |data|
  next if data.bot_id # Bot自身のメッセージは無視
  next unless data.text&.include?('<@') # メンションのみ反応

  query = data.text.gsub(/<@[A-Z0-9]+>/, '').strip

  # NDJSONから検索
  results = NdjsonSearch.search('knowledge.ndjson', query)

  if results.empty?
    client.web_client.chat_postMessage(
      channel: data.channel,
      text: "該当するドキュメントが見つかりませんでした。",
      thread_ts: data.ts
    )
    next
  end

  # 検索結果をLLMに渡して回答生成
  context = results.map do |doc|
    "## #{doc['title']}\n#{doc['content']}"
  end.join("\n\n")

  prompt = <<~PROMPT
    以下のドキュメントを参考に、ユーザーの質問に回答してください。

    【ドキュメント】
    #{context}

    【質問】
    #{query}
  PROMPT

  response = OpencodeClient.chat(prompt)

  client.web_client.chat_postMessage(
    channel: data.channel,
    text: response,
    thread_ts: data.ts
  )
end

client.start!
```

### 4. OpenCode クライアント

```ruby
# lib/opencode_client.rb
require 'faraday'

module OpencodeClient
  OPENCODE_URL = ENV.fetch('OPENCODE_URL', 'http://localhost:4096')

  class << self
    def chat(message)
      conn = connection

      # セッション作成
      session_res = conn.post('/session')
      session = JSON.parse(session_res.body)

      # メッセージ送信
      res = conn.post("/session/#{session['id']}/message") do |req|
        req.body = { content: message }.to_json
      end

      result = JSON.parse(res.body)
      result['content']
    end

    private

    def connection
      @connection ||= Faraday.new(url: OPENCODE_URL) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end
  end
end
```

## 起動方法

```bash
# ターミナル1: OpenCode Serverを起動
opencode --hostname localhost --port 4096

# ターミナル2: Slack Botを起動
SLACK_BOT_TOKEN=xoxb-xxx SLACK_APP_TOKEN=xapp-xxx ruby slack_bot.rb
```

Slackで `@bot デプロイ手順教えて` と投稿すると：

1. BotがSocket Mode経由でメッセージを受信
2. NDJSONから「デプロイ」に関連するドキュメントを検索
3. 検索結果をOpenCode Server経由でLLMに送信
4. LLMが回答を生成
5. Slackスレッドに回答を投稿

## なぜこのアーキテクチャが良いのか

### 1. 運用がシンプル

```
RAG構成:
- Embedding APIの契約・課金管理
- ベクトルDBのホスティング
- インデックス再構築の運用
- チャンク戦略の調整

NDJSON構成:
- ファイルを1つ管理するだけ
```

### 2. デバッグが容易

```bash
# 何が検索されているか一目瞭然
grep "デプロイ" knowledge.ndjson

# ドキュメントの追加・修正が即座に反映
vim knowledge.ndjson
```

### 3. Git管理と相性がいい

```bash
git diff knowledge.ndjson
# + {"id": "doc-005", "title": "新しい手順", ...}

git log --oneline knowledge.ndjson
# ナレッジの変更履歴が追跡可能
```

### 4. コストが低い

- Embedding APIの呼び出し: **不要**
- ベクトルDBのホスティング: **不要**
- 必要なのはLLM APIの呼び出しのみ

## RAGが必要になるとき

もちろん、RAGが必要なケースもある：

| NDJSON検索で十分 | RAGが必要 |
|-----------------|----------|
| ドキュメント数千件以下 | 数万件以上 |
| キーワードマッチで探せる | 意味的類似性が必要 |
| 構造化されたデータ | 非構造化テキスト大量 |
| リアルタイム更新重視 | 精度最優先 |

システムが成長してきたら、NDJSONからベクトルDBへの移行を検討すればいい。最初からRAGを構築する必要はない。

## 発展: 複数ファイル対応

ナレッジが増えてきたら、カテゴリごとにファイルを分割できる：

```
knowledge/
├── processes.ndjson    # 業務プロセス
├── tech.ndjson         # 技術ドキュメント
├── faq.ndjson          # よくある質問
└── incidents.ndjson    # 障害事例
```

```ruby
# 複数ファイルを横断検索
Dir.glob('knowledge/*.ndjson').flat_map do |file|
  NdjsonSearch.search(file, query, limit: 3)
end.sort_by { |doc| -doc[:score] }.first(5)
```

## まとめ

NDJSON + OpenCode + Slack Bot (Socket Mode) の組み合わせで：

1. **RAG不要**：ベクトルDBなしでナレッジ検索
2. **Socket Mode**：ローカルでも動作するSlack Bot
3. **シンプル運用**：ファイル1つで完結
4. **即座に反映**：ナレッジ追加は1行追記

「とりあえずRAG」と考える前に、**本当にRAGが必要か**を考えてみよう。多くのケースで、このシンプルなアーキテクチャで十分だ。

まずは小さく始めて、必要になったら複雑化すればいい。

---

## 参考リンク

- [NDJSON 仕様](http://ndjson.org/)
- [Slack Socket Mode](https://api.slack.com/apis/connections/socket)
- [OpenCode Server](https://opencode.ai/docs/server/)
- [slack-ruby-client](https://github.com/slack-ruby/slack-ruby-client)
