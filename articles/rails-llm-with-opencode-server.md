---
title: "RailsでLLM活用サービスを作る：OpenCode Serverという選択肢"
emoji: "🚂"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Rails", "Ruby", "LLM", "OpenCode", "AI"]
published: true
---

## はじめに

RubyとRailsでLLMを活用したサービスを作りたい。しかし、TypeScriptやPythonに比べると、RubyのAI/LLMエコシステムはまだ発展途上だ。

LangChainはPython/JS版が主流で、OpenAI公式SDKもRuby版はコミュニティメンテナンス。新しいモデルやプロバイダーが出てきたとき、Rubyでの対応が遅れることは珍しくない。

そこで紹介したいのが**OpenCode Server**だ。LLMとのやりとりをHTTP APIで抽象化し、**言語を選ばずにLLM機能を利用できる**仕組みを提供してくれる。

## OpenCodeとは

[OpenCode](https://github.com/sst/opencode)は、SSTが開発したオープンソースのAIコーディングエージェントだ。GitHubスター41k以上を誇る人気プロジェクトで、完全にオープンソースで提供されている。

特徴的なのは、その**クライアント/サーバーアーキテクチャ**だ。

```
通常のLLMライブラリ:
アプリケーション → LLMライブラリ(言語固有) → LLM API

OpenCode Server経由:
アプリケーション → HTTP API → OpenCode Server → 任意のLLM
```

OpenCodeをサーバーモードで起動すると、HTTP APIを通じてLLM機能にアクセスできる。つまり、**Rubyだろうが、PHPだろうが、curlだろうが**、HTTPが使えれば何でもLLMと対話できる。

## OpenCode Serverのセットアップ

### インストール

```bash
# シェルスクリプトでインストール
curl -fsSL https://opencode.ai/install | bash

# または npm
npm install -g @opencode-ai/cli

# または Homebrew
brew install sst/tap/opencode
```

### サーバーモードで起動

```bash
# ポートを指定してサーバーモードで起動
opencode --hostname localhost --port 4096
```

TUIを起動すると自動的にHTTPサーバーも立ち上がる。`http://localhost:4096/doc`にアクセスすると、OpenAPI仕様のドキュメントが確認できる。

### LLMプロバイダーの設定

OpenCodeは75以上のLLMプロバイダーをサポートしている。設定は`opencode.json`で行う：

```json
{
  "provider": {
    "name": "anthropic",
    "apiKey": "${ANTHROPIC_API_KEY}"
  }
}
```

Claude、OpenAI、Google、Grokなど、好みのプロバイダーを選べる。

## RailsからOpenCode Serverを使う

### 基本的なHTTPリクエスト

Railsから使う場合、特別なgemは不要だ。標準のHTTPクライアントで十分。

```ruby
# app/services/opencode_client.rb
class OpencodeClient
  include HTTParty
  base_uri 'http://localhost:4096'

  def self.create_session
    post('/session', body: {}.to_json, headers: json_headers)
  end

  def self.send_message(session_id, content)
    post("/session/#{session_id}/message",
      body: { content: content }.to_json,
      headers: json_headers
    )
  end

  private

  def self.json_headers
    { 'Content-Type' => 'application/json' }
  end
end
```

### ストリーミング対応

OpenCode ServerはServer-Sent Events（SSE）でストリーミングレスポンスに対応している。

```ruby
# app/services/opencode_stream.rb
require 'net/http'

class OpencodeStream
  def self.stream_response(session_id, &block)
    uri = URI("http://localhost:4096/event")

    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'text/event-stream'

      http.request(request) do |response|
        response.read_body do |chunk|
          block.call(parse_sse(chunk))
        end
      end
    end
  end

  private

  def self.parse_sse(chunk)
    # SSEイベントをパース
    JSON.parse(chunk.gsub(/^data: /, '')) rescue nil
  end
end
```

### Railsコントローラーでの利用例

```ruby
# app/controllers/api/chat_controller.rb
class Api::ChatController < ApplicationController
  def create
    session = OpencodeClient.create_session
    response = OpencodeClient.send_message(
      session['id'],
      params[:message]
    )

    render json: { response: response['content'] }
  end

  def stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'

    session = OpencodeClient.create_session

    OpencodeStream.stream_response(session['id']) do |event|
      response.stream.write("data: #{event.to_json}\n\n")
    end
  ensure
    response.stream.close
  end
end
```

## ライブラリ非依存のメリット

OpenCode Serverを使うアーキテクチャには、大きなメリットがある。

### 1. プロバイダー切り替えが容易

```ruby
# アプリケーションコードを一切変えずに
# OpenCodeの設定だけでプロバイダーを切り替え可能

# opencode.json を変えるだけ
# Claude → GPT-4 → Grok → ローカルモデル
```

アプリケーションはHTTP APIを叩くだけなので、バックエンドのLLMが何であろうと関係ない。

### 2. Ruby側のgemに依存しない

```ruby
# ❌ 従来のアプローチ
# Gemfile
gem 'ruby-openai'  # メンテナンス状況が不安
gem 'anthropic'    # 新機能対応が遅れがち

# ✅ OpenCode経由
# 特別なgemは不要。HTTPartyやFaradayなど
# 汎用HTTPクライアントだけでOK
```

LLM固有のgemに依存しないため、gemのメンテナンス状況を気にする必要がない。

### 3. テストが容易

```ruby
# spec/services/opencode_client_spec.rb
RSpec.describe OpencodeClient do
  it 'sends message to OpenCode server' do
    # 単純なHTTPモックでテスト可能
    stub_request(:post, 'http://localhost:4096/session/123/message')
      .to_return(body: { content: 'Hello!' }.to_json)

    response = OpencodeClient.send_message('123', 'Hi')
    expect(response['content']).to eq('Hello!')
  end
end
```

HTTP APIなので、WebMockなどの標準的なツールでテストできる。

## Grokが無料で使える

ここで朗報がある。**xAIのGrok Code Fast 1が、OpenCode経由なら期間限定で無料**で使える。

OpenCodeは、xAIの公式ローンチパートナーに選ばれている。GitHub Copilot、Cursor、Clineなどと並んで、Grokを無料で試せる環境が提供されている。

```json
// opencode.json
{
  "provider": {
    "name": "xai",
    "model": "grok-code-fast-1"
  }
}
```

Grok Code Fast 1の特徴：

- **高速**：名前の通り、レスポンスが速い
- **コーディング特化**：TypeScript、Python、Java、Rust、C++、Goに強い
- **低コスト**：無料期間終了後も、$0.20/1M入力トークンと安価

まずは無料で試してみて、本番では用途に応じてプロバイダーを選ぶという戦略が取れる。

## RubyがAIに弱い？それを強みに変える

正直に言おう。**RubyのAI/MLエコシステムは、PythonやTypeScriptに比べて弱い**。

- TensorFlow/PyTorch → Python一択
- LangChain → Python/JS版が主流
- OpenAI SDK → 公式はPython/JS、Ruby版はコミュニティ

しかし、これを別の視点で見てみよう。

### 関心の分離ができる

```
Python/TSの世界:
アプリケーション ＋ AI/MLロジック ＋ LLMライブラリ
（すべてが密結合）

OpenCode + Railsの世界:
Rails（Webアプリケーション）
    ↓ HTTP API
OpenCode Server（AI/LLMの責務）
    ↓
任意のLLMプロバイダー
```

Railsは得意なこと（Webアプリケーション開発）に集中し、AI/LLMの複雑さはOpenCode Serverに任せる。これは**責務の分離**という観点では、むしろ健全なアーキテクチャだ。

### デプロイも分離できる

```yaml
# docker-compose.yml
services:
  rails:
    build: ./rails
    depends_on:
      - opencode
    environment:
      OPENCODE_URL: http://opencode:4096

  opencode:
    image: opencode/server
    ports:
      - "4096:4096"
    environment:
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
```

Railsアプリとは別のコンテナ/サービスとしてデプロイできる。スケーリングも独立して行える。

## 実践：シンプルなチャットボットを作る

最後に、実際にRails + OpenCode Serverでチャットボットを作ってみよう。

### 1. Railsプロジェクトの準備

```bash
rails new chatbot_app --api
cd chatbot_app
```

### 2. OpenCodeクライアントの実装

```ruby
# app/services/llm_service.rb
class LlmService
  OPENCODE_URL = ENV.fetch('OPENCODE_URL', 'http://localhost:4096')

  def initialize
    @connection = Faraday.new(url: OPENCODE_URL) do |f|
      f.request :json
      f.response :json
    end
  end

  def chat(message, context: [])
    session = create_session

    # コンテキストがあれば先に送信
    context.each do |msg|
      send_message(session['id'], msg)
    end

    # メインのメッセージを送信
    response = send_message(session['id'], message)
    response['content']
  end

  private

  def create_session
    response = @connection.post('/session')
    response.body
  end

  def send_message(session_id, content)
    response = @connection.post("/session/#{session_id}/message") do |req|
      req.body = { content: content }
    end
    response.body
  end
end
```

### 3. コントローラー

```ruby
# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  def create
    llm = LlmService.new
    response = llm.chat(params[:message])

    render json: { message: response }
  end
end
```

### 4. 動作確認

```bash
# ターミナル1: OpenCode Serverを起動
opencode --hostname localhost --port 4096

# ターミナル2: Railsサーバーを起動
rails server

# ターミナル3: リクエストを送信
curl -X POST http://localhost:3000/chats \
  -H "Content-Type: application/json" \
  -d '{"message": "Rubyの良いところを3つ教えて"}'
```

これだけで、RailsアプリケーションからLLMを利用できる。

## まとめ

OpenCode Serverを使うことで：

1. **ライブラリ非依存**：Ruby固有のLLMライブラリに依存しない
2. **プロバイダー切り替え自由**：設定変更だけでClaude/GPT/Grok/ローカルモデルを切り替え
3. **関心の分離**：RailsはWebアプリに集中、LLMの複雑さはOpenCodeに委譲
4. **Grok無料**：期間限定でGrok Code Fast 1が無料で使える

RubyのAIエコシステムが弱いことを嘆くより、**HTTPという最も汎用的なインターフェース**を使って解決する。これがOpenCode Serverというアプローチだ。

まずは無料のGrokで試してみてほしい。5分のセットアップで、RailsアプリからLLMが使えるようになる。

---

## 参考リンク

- [OpenCode 公式サイト](https://opencode.ai/)
- [OpenCode GitHub](https://github.com/sst/opencode)
- [OpenCode Server ドキュメント](https://opencode.ai/docs/server/)
- [xAI Grok API](https://x.ai/api)
- [Grok Code Fast 1 発表](https://x.ai/news/grok-code-fast-1)
