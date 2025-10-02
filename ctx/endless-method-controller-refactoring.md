# Endless メソッドでコントローラーを1行化する記事のコンテキスト

## 記事の目的
Ruby/Rails で endless メソッドを軸にコントローラーの責務を極限まで削ぎ落とし、宣言的な組み立てでビジネスロジックをモデル周辺へ移すアプローチを整理する。具体的には次の価値を掘り下げる:

- 肥大化しがちなコントローラーを Ruby の動的性質で分解し、最終的に1行のエントリーポイントへ集約する。
- リクエスト処理とパラメータ検証を疎結合にし、IRB からの操作やテストを容易にすることで画面リロードに頼らない検証フローを実現する。
- 宣言的なフロー定義からイベント的なエンティティを導出し、更新ロジックや非同期処理を見通し良く整理する手段を検討する。

この背景を踏まえ、具体的な組み立て方・パターン・トレードオフを記事で示す。

## 対象記事
`articles/a4d711bc1d3193.md`

## 要件・制約

### 1. Service クラスは使わない（悪手）
- Service クラスは責務が曖昧になりがち
- 代わりにモデルから移譲したドメインロジッククラスを使う

### 2. フロントエンドは Inertia.js + React
- tsx コードは省略（記事に含めない）
- サーバーサイドのコードに集中

### 3. Namespace を利用
- コントローラー: `Auth::RegistrationsController` など
- ドメインロジック: `Users::Registration` など

### 4. モデル経由でドメインロジックにアクセス
```ruby
# モデルにドメインロジックへの糊付けメソッドを定義
class User < ApplicationRecord
  def registration = Users::Registration.new(self)
  def sms_verification_sender = Users::SmsVerificationSender.new(self)
end

# 使用例
user.registration.call
user.sms_verification_sender.call_later
```

## 使用するモジュール

### CallLater パターン
```ruby
module CallLater
  def self.define(model, queue_as: :default)
    # call_later メソッドを自動生成
    # バックグラウンドジョブクラスを動的に作成
    # GlobalID によるシリアライズ対応
  end
end
```

### Delayed モジュール
```ruby
module Delayed
  def self.define(namespace, name = :call, queue_as: :default, wait: nil, attempts: nil)
    # 非同期実行用のジョブクラスを動的生成
  end
end
```

## 実装例: SMS認証付きユーザー登録

### フロー
1. ユーザー登録 → SMS認証コード送信（非同期）
2. SMS認証コード入力 → 検証 → ユーザー有効化 → ウェルカムメール送信（非同期）

### ドメインの切り出しに関する課題

**現状の問題点:**
```ruby
Users::Registration  # ユーザー登録
Users::SmsVerificationSender  # SMS送信
Users::SmsVerificationValidator  # SMS検証
Users::WelcomeEmailSender  # ウェルカムメール
```

→ 責務がバラバラで、本来の流れが見えにくい

**検討中の改善案:**

**案1: SMS認証を独立したドメインに**
```ruby
User#register  # ユーザー登録
SmsVerification#send_code  # コード送信
SmsVerification#verify  # コード検証
User#send_welcome_email  # ウェルカムメール
```

**案2: フローごとに整理**
```ruby
User#register  # 登録してSMS送信まで
SmsVerification#verify_and_activate  # 検証してユーザー有効化
```

## 目指すコントローラーの形

```ruby
module Auth
  class RegistrationsController < ApplicationController
    # 1行で完結
    def create = respond_with_registration(user.registration.call)
    
    private
    
    def user = User.new(user_params)
    def user_params = params.require(:user).permit(:name, :phone_number)
  end
end
```

## 記事の構成案

1. はじめに
2. 前提: CallLater と Delayed モジュール
3. SMS認証付きユーザー登録の実装
   - モデルの定義
   - ドメインロジッククラス（namespace で整理）
   - モデルからの糊付け
   - コントローラー（1行化）
4. アーキテクチャのポイント
   - Service クラスを使わない理由
   - CallLater パターンの威力
   - Endless メソッドで可読性向上
   - Namespace で責務を整理
5. メリット
6. まとめ

## 次のステップ
- ドメインの切り出し方を決定
- モデル経由のアクセスパターンを整理
- コントローラーの1行化を実現