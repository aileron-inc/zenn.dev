---
title: "NDJSONが凄い理由：ストリーミング処理とログに最適なデータフォーマット"
emoji: "📜"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["JSON", "NDJSON", "データ処理", "ログ", "ストリーミング"]
published: true
---

## NDJSONとは

NDJSON（Newline Delimited JSON）は、各行が独立したJSONオブジェクトとなるシンプルなフォーマットだ。

```json
{"id": 1, "name": "Alice", "action": "login"}
{"id": 2, "name": "Bob", "action": "purchase"}
{"id": 3, "name": "Charlie", "action": "logout"}
```

通常のJSON配列との違いを比較してみよう。

```json
// 通常のJSON配列
[
  {"id": 1, "name": "Alice", "action": "login"},
  {"id": 2, "name": "Bob", "action": "purchase"},
  {"id": 3, "name": "Charlie", "action": "logout"}
]
```

この単純な違いが、実際の運用では大きなメリットをもたらす。

## NDJSONが優れている5つの理由

### 1. ストリーミング処理が可能

通常のJSONは、ファイル全体を読み込んでパースする必要がある。

```ruby
# 通常のJSON - 全体をメモリに読み込む
data = JSON.parse(File.read("huge_file.json"))
data.each { |record| process(record) }
```

NDJSONなら1行ずつ処理できる。

```ruby
# NDJSON - 1行ずつ処理
File.foreach("huge_file.ndjson") do |line|
  record = JSON.parse(line)
  process(record)
end
```

10GBのログファイルでも、メモリ使用量は1行分だけで済む。

### 2. 追記が簡単

通常のJSON配列に要素を追加するには、ファイル全体を読み込んで書き直す必要がある。

```ruby
# 通常のJSON - 追記が面倒
data = JSON.parse(File.read("data.json"))
data << new_record
File.write("data.json", JSON.pretty_generate(data))
```

NDJSONなら単純に追記するだけ。

```ruby
# NDJSON - 追記が簡単
File.open("data.ndjson", "a") do |f|
  f.puts(new_record.to_json)
end
```

ログ収集やイベント記録に最適だ。

### 3. Unix ツールとの相性が抜群

各行が独立しているため、標準的なUnixツールがそのまま使える。

```bash
# 最新10件を取得
tail -n 10 events.ndjson

# 特定のユーザーを検索
grep '"user_id": 42' events.ndjson

# エラーだけ抽出
grep '"level": "error"' logs.ndjson | head -n 100

# 行数 = レコード数
wc -l events.ndjson

# 特定フィールドを抽出（jqと組み合わせ）
cat events.ndjson | jq -r '.action' | sort | uniq -c
```

通常のJSON配列では、こうした操作に専用のパーサーが必要になる。

### 4. 障害耐性が高い

通常のJSONは、途中で破損すると全体が読めなくなる。

```json
[
  {"id": 1, "name": "Alice"},
  {"id": 2, "name": "Bob"   // ← ここで破損
  {"id": 3, "name": "Charlie"}
]
// 全体がパースエラー
```

NDJSONなら、壊れた行をスキップして残りを処理できる。

```ruby
File.foreach("data.ndjson") do |line|
  begin
    record = JSON.parse(line)
    process(record)
  rescue JSON::ParserError
    # この行だけスキップ、他は処理続行
    log_error("Invalid JSON: #{line}")
  end
end
```

### 5. 並列処理との相性が良い

行単位で分割できるため、並列処理が容易だ。

```ruby
# Rubyでの並列処理例
require 'parallel'

lines = File.readlines("large_data.ndjson")
results = Parallel.map(lines, in_processes: 4) do |line|
  record = JSON.parse(line)
  heavy_processing(record)
end
```

```bash
# GNU parallelでの処理
cat huge.ndjson | parallel --pipe -L 1000 'process_batch.rb'
```

## 実践的なユースケース

### ログ収集

```ruby
# config/initializers/structured_logging.rb
class NdjsonLogger
  def initialize(path)
    @file = File.open(path, "a")
  end

  def log(level:, message:, **metadata)
    entry = {
      timestamp: Time.current.iso8601,
      level: level,
      message: message,
      **metadata
    }
    @file.puts(entry.to_json)
  end
end

# 使用例
logger = NdjsonLogger.new("logs/app.ndjson")
logger.log(level: "info", message: "User logged in", user_id: 42)
```

### APIのバルクレスポンス

```ruby
# app/controllers/exports_controller.rb
class ExportsController < ApplicationController
  def users
    response.headers["Content-Type"] = "application/x-ndjson"

    User.find_each do |user|
      response.stream.write(user.to_json + "\n")
    end
  ensure
    response.stream.close
  end
end
```

### データパイプライン

```ruby
# ETLパイプラインでの使用
class DataPipeline
  def extract(source_path)
    Enumerator.new do |y|
      File.foreach(source_path) do |line|
        y << JSON.parse(line)
      end
    end
  end

  def transform(records)
    records.lazy.map do |record|
      # 変換処理
      record.merge(processed_at: Time.current.iso8601)
    end
  end

  def load(records, dest_path)
    File.open(dest_path, "w") do |f|
      records.each { |r| f.puts(r.to_json) }
    end
  end

  def run(source, dest)
    load(transform(extract(source)), dest)
  end
end
```

### 大規模データのインポート

```ruby
# db/seeds/import_users.rb
File.foreach("users.ndjson").with_index do |line, i|
  user_data = JSON.parse(line)
  User.create!(user_data)

  puts "Imported #{i + 1} users" if (i + 1) % 1000 == 0
end
```

## NDJSONを扱うツール

### jq

```bash
# 各行を整形して表示
cat data.ndjson | jq .

# 特定フィールドを抽出
cat data.ndjson | jq -r '.email'

# フィルタリング
cat data.ndjson | jq 'select(.age > 30)'

# 集計
cat data.ndjson | jq -s 'group_by(.status) | map({status: .[0].status, count: length})'
```

### Ruby標準ライブラリ

特別なgemは不要。標準のJSONライブラリだけで十分。

```ruby
require 'json'

# 読み込み
records = File.readlines("data.ndjson").map { |line| JSON.parse(line) }

# 書き込み
File.open("output.ndjson", "w") do |f|
  records.each { |r| f.puts(r.to_json) }
end
```

### Node.js

```javascript
const fs = require('fs');
const readline = require('readline');

async function processNdjson(filePath) {
  const fileStream = fs.createReadStream(filePath);
  const rl = readline.createInterface({ input: fileStream });

  for await (const line of rl) {
    const record = JSON.parse(line);
    console.log(record);
  }
}
```

## 通常のJSONとの使い分け

| 用途 | 推奨フォーマット | 理由 |
|------|-----------------|------|
| APIレスポンス（単一） | JSON | クライアントの互換性 |
| 設定ファイル | JSON | 人間が編集しやすい |
| ログファイル | NDJSON | 追記・検索が容易 |
| 大量データ転送 | NDJSON | ストリーミング可能 |
| バックアップ | NDJSON | 追記・分割が容易 |
| イベント記録 | NDJSON | 時系列での追記 |
| データ交換 | NDJSON | 並列処理しやすい |

## MIMEタイプ

NDJSONのMIMEタイプは `application/x-ndjson` だ。

```ruby
# Railsでの設定
Mime::Type.register "application/x-ndjson", :ndjson

# コントローラーでの使用
respond_to do |format|
  format.ndjson { render_ndjson(@records) }
end
```

## まとめ

NDJSONの強み：

- **メモリ効率**: 巨大ファイルも1行ずつ処理
- **追記容易**: ログやイベントの記録に最適
- **Unix親和性**: grep, tail, wc がそのまま使える
- **障害耐性**: 部分的な破損に強い
- **並列処理**: 行単位で分割可能

シンプルな改行区切りという設計が、実運用で大きな価値を発揮する。ログ収集、データパイプライン、バルクエクスポートなど、大量データを扱う場面ではNDJSONを検討してみよう。

---

## 参考リンク

- [NDJSON Specification](http://ndjson.org/)
- [JSON Lines](https://jsonlines.org/)
- [jq Manual](https://stedolan.github.io/jq/manual/)
