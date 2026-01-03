---
title: "NDJSON + OpenCode + Slack Bot：RAGを使わないシンプル検索システム"
emoji: "🔍"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["NDJSON", "OpenCode", "Slack", "Bot", "検索"]
published: true
---

## はじめに

RAG（Retrieval-Augmented Generation）は強力だ。ベクトル検索で関連ドキュメントを取得し、LLMに渡す。しかし、すべてのユースケースにRAGが必要だろうか？

実は、**LLMに直接NDJSONファイルを読ませて「検索して」とお願いするだけ**で、多くのケースは解決する。

```
RAGアーキテクチャ:
ドキュメント → Embedding → ベクトルDB → 類似検索 → LLM → 回答

シンプルアーキテクチャ:
NDJSON → OpenCodeが直接読んで検索 → 回答
```

検索ロジックすら自分で書く必要がない。OpenCodeにファイルを渡して「探して」と言えばいい。

## 発想の転換

従来の考え方：
```
1. 検索システムを実装する
2. 検索結果をLLMに渡す
3. LLMが回答を生成する
```

新しい考え方：
```
1. NDJSONファイルをOpenCodeに渡す
2. 「この中から〇〇を探して回答して」とお願いする
3. 終わり
```

**検索もLLMにやらせればいい。** OpenCodeはファイルを読む能力がある。NDJSONの各行を見て、関連する情報を見つけ出すのはLLMの得意技だ。

## NDJSONとは

NDJSON（Newline Delimited JSON）は、1行1JSONオブジェクトの形式だ。

```ndjson
{"id": 1, "name": "田中太郎", "interests": ["Ruby", "Rails"], "skill_level": "senior"}
{"id": 2, "name": "鈴木花子", "interests": ["Python", "機械学習"], "skill_level": "middle"}
{"id": 3, "name": "佐藤次郎", "interests": ["Go", "Kubernetes"], "skill_level": "senior"}
```

### なぜNDJSONか

- **1行1レコード**：LLMが読みやすい
- **追記が簡単**：新しいレコードは末尾に1行追加
- **grep互換**：デバッグも簡単
- **Git管理**：差分が行単位で見える

## システム構成

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│  Slack Bot  │ ──→  │   OpenCode   │ ──→  │  NDJSON     │
│(Socket Mode)│      │   Server     │      │  ファイル   │
└─────────────┘      └──────────────┘      └─────────────┘
                            │
                            ↓
                     ┌──────────────┐
                     │     LLM      │
                     │ (検索も回答も)│
                     └──────────────┘
```

ポイントは**検索ロジックがない**こと。OpenCodeがNDJSONを読み、LLMが検索も回答生成も両方やる。

## 実装例：社内メンバーレコメンド

### 1. NDJSONでメンバー情報を管理

```ndjson
{"id": 1, "name": "田中太郎", "department": "開発", "skills": ["Ruby", "Rails", "PostgreSQL"], "projects": ["ECサイト", "API基盤"]}
{"id": 2, "name": "鈴木花子", "department": "開発", "skills": ["Python", "TensorFlow", "データ分析"], "projects": ["レコメンドエンジン"]}
{"id": 3, "name": "佐藤次郎", "department": "インフラ", "skills": ["AWS", "Terraform", "Kubernetes"], "projects": ["クラウド移行"]}
{"id": 4, "name": "山田三郎", "department": "開発", "skills": ["TypeScript", "React", "Next.js"], "projects": ["管理画面刷新"]}
{"id": 5, "name": "伊藤四郎", "department": "開発", "skills": ["Go", "gRPC", "マイクロサービス"], "projects": ["決済基盤"]}
```

### 2. Slack Botの実装

```ruby
# slack_bot.rb
require 'slack-ruby-client'
require 'faraday'

Slack.configure do |config|
  config.token = ENV['SLACK_BOT_TOKEN']
end

client = Slack::RealTime::Client.new

client.on :message do |data|
  next if data.bot_id
  next unless data.text&.include?('<@')

  query = data.text.gsub(/<@[A-Z0-9]+>/, '').strip

  # NDJSONファイルの内容を読む
  members_ndjson = File.read('members.ndjson')

  # OpenCodeに「検索して」とお願いするだけ
  prompt = <<~PROMPT
    以下はメンバー情報のNDJSONです。各行が1人のメンバーを表しています。

    ```ndjson
    #{members_ndjson}
    ```

    ユーザーからの質問: #{query}

    この質問に最も適したメンバーを探して、なぜその人が適任なのか説明してください。
  PROMPT

  response = opencode_chat(prompt)

  client.web_client.chat_postMessage(
    channel: data.channel,
    text: response,
    thread_ts: data.ts
  )
end

def opencode_chat(message)
  conn = Faraday.new(url: 'http://localhost:4096')
  session = JSON.parse(conn.post('/session').body)
  res = conn.post("/session/#{session['id']}/message") do |req|
    req.headers['Content-Type'] = 'application/json'
    req.body = { content: message }.to_json
  end
  JSON.parse(res.body)['content']
end

client.start!
```

### 3. 使ってみる

Slackで：
```
@bot Kubernetes詳しい人いる？
```

Botの回答：
```
佐藤次郎さんがおすすめです。

理由：
- スキルにKubernetesを持っています
- インフラ部門でクラウド移行プロジェクトを担当
- AWS、Terraformも扱えるので、インフラ全般の相談が可能です
```

**検索ロジックは一切書いていない。** OpenCodeにNDJSONを渡して「探して」と言っただけ。

## なぜこれで十分なのか

### LLMの能力を活かす

LLMは：
- JSONを読める
- 文脈を理解できる
- 「似ている」を判断できる

わざわざベクトル検索を挟む必要がない。「Kubernetes詳しい人」という質問に対して、スキルに「Kubernetes」があるレコードを見つけるのは、LLMにとって簡単な作業だ。

### 規模の問題

「でも大量のデータだと？」

確かにNDJSONが1万行あったら、全部をプロンプトに入れるのは現実的ではない。しかし：

- 社内メンバー：数十〜数百人
- 商品カタログ（小規模）：数百〜数千件
- FAQ：数十〜数百件

これくらいの規模なら、全部プロンプトに入れても問題ない。**RAGが必要になるのは、もっと大規模になってから**だ。

## 応用例

### 商品レコメンド

```ndjson
{"id": "p001", "name": "ワイヤレスイヤホン", "category": "オーディオ", "price": 15000, "features": ["ノイズキャンセリング", "防水", "長時間再生"]}
{"id": "p002", "name": "有線イヤホン", "category": "オーディオ", "price": 3000, "features": ["高音質", "軽量"]}
```

```
@bot 予算1万円でノイキャン付きのイヤホンある？
```

### 社内FAQ

```ndjson
{"q": "有給の申請方法は？", "a": "勤怠システムから申請してください。上長承認が必要です。"}
{"q": "経費精算の締め日は？", "a": "毎月25日です。26日以降は翌月処理になります。"}
```

```
@bot 経費っていつまでに出せばいい？
```

### ナレッジベース

```ndjson
{"title": "本番デプロイ手順", "content": "1. PRをマージ 2. CI通過を確認 3. デプロイボタンをクリック"}
{"title": "障害対応フロー", "content": "1. #incident チャンネルに報告 2. 影響範囲を特定 3. 復旧作業"}
```

```
@bot デプロイってどうやるんだっけ？
```

## Socket Modeを使う理由

Slack Botには2つの接続方式がある：

| 方式 | 特徴 |
|------|------|
| HTTP (Webhook) | 公開URLが必要 |
| **Socket Mode** | WebSocket接続、ローカルでも動作 |

Socket Modeなら：
- ngrokなどのトンネリング不要
- ファイアウォール内でも動作
- ローカル開発が簡単

## まとめ

```
従来: データ → 検索システム構築 → ベクトルDB → RAG → LLM
今回: データ → NDJSON → OpenCodeに渡す → 終わり
```

小規模なデータなら、**検索もLLMにやらせればいい**。

- メンバー検索
- 商品レコメンド
- FAQ検索
- ナレッジベース

これらは数百〜数千件程度。NDJSONをそのままLLMに渡して「探して」とお願いするだけで動く。

RAGは強力だが、**必要になるまで導入しなくていい**。まずはNDJSON + OpenCodeのシンプルな構成で始めよう。

---

## 参考リンク

- [NDJSON 仕様](http://ndjson.org/)
- [Slack Socket Mode](https://api.slack.com/apis/connections/socket)
- [OpenCode](https://opencode.ai/)
