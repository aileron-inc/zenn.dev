---
title: "Railsでプロパティベーステスト入門：PropCheckとpbtで堅牢なテストを書く"
emoji: "🎲"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Rails", "Ruby", "テスト", "RSpec", "PropCheck"]
published: true
---

## プロパティベーステストとは

通常のユニットテストでは「この入力に対して、この出力を期待する」という形式でテストを書く。

```ruby
# 通常のテスト
it "sorts numbers correctly" do
  expect([3, 1, 2].sort).to eq([1, 2, 3])
end
```

一方、**プロパティベーステスト**では「どんな入力に対しても、この性質が成り立つ」という形式でテストを書く。

```ruby
# プロパティベーステスト
it "sorted array is always in ascending order" do
  PropCheck.forall(G.array(G.integer)) do |numbers|
    sorted = numbers.sort
    sorted.each_cons(2) { |a, b| a <= b }
  end
end
```

## なぜプロパティベーステストが必要か

通常のテストには限界がある。

| 問題 | 説明 |
|------|------|
| カバレッジの罠 | 100%カバレッジでもエッジケースを見逃す |
| 開発者のバイアス | 思いつく範囲でしかテストできない |
| 境界値の見落とし | 0, -1, 空配列, nil などの考慮漏れ |

プロパティベーステストは、ランダムな入力を大量に生成してテストするため、**開発者が思いつかないエッジケース**を発見できる。

## RubyのプロパティベーステストGem

Rubyには主に2つのプロパティベーステスト用gemがある。

### 1. PropCheck

最も活発にメンテナンスされているgem。

```ruby
# Gemfile
gem 'prop_check', group: :test
```

### 2. pbt

Ractorによる並行実行をサポート。RubyKaigi 2024で紹介された。

```ruby
# Gemfile
gem 'pbt', group: :test
```

## PropCheckの基本的な使い方

### セットアップ

```ruby
# spec/rails_helper.rb
require 'prop_check'
require 'prop_check/rspec'
```

### 基本構文

```ruby
G = PropCheck::Generators

RSpec.describe "ソートのプロパティ" do
  include PropCheck::RSpec

  it "ソート後の配列は昇順になる" do
    forall(G.array(G.integer)) do |numbers|
      sorted = numbers.sort
      sorted.each_cons(2).all? { |a, b| a <= b }
    end
  end

  it "ソート後の配列は元の配列と同じ要素を持つ" do
    forall(G.array(G.integer)) do |numbers|
      sorted = numbers.sort
      sorted.sort == numbers.sort
    end
  end
end
```

### 主要なジェネレータ

PropCheckには豊富なジェネレータが用意されている。

```ruby
G = PropCheck::Generators

# 数値
G.integer              # 任意の整数
G.positive_integer     # 正の整数
G.negative_integer     # 負の整数
G.float                # 浮動小数点数

# 文字列
G.string               # 任意の文字列
G.alphanumeric_string  # 英数字のみ
G.ascii_string         # ASCII文字のみ

# コレクション
G.array(G.integer)          # 整数の配列
G.hash(G.symbol, G.string)  # シンボルキー、文字列値のハッシュ

# 選択
G.one_of(G.integer, G.string)  # 整数か文字列
G.constant(42)                  # 固定値

# 組み合わせ
G.tuple(G.integer, G.string)   # [整数, 文字列] のタプル
```

## Railsモデルでの実践例

### バリデーションのテスト

```ruby
# app/models/user.rb
class User < ApplicationRecord
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :age, numericality: { greater_than_or_equal_to: 0, less_than: 150 }
end
```

```ruby
# spec/models/user_property_spec.rb
require 'rails_helper'
require 'prop_check'

RSpec.describe User do
  G = PropCheck::Generators

  # 有効なメールアドレスジェネレータ
  let(:valid_email) do
    G.alphanumeric_string.map { |s| "#{s.presence || 'user'}@example.com" }
  end

  # 有効な年齢ジェネレータ
  let(:valid_age) do
    G.choose(0, 149)
  end

  describe "age validation" do
    it "0以上150未満の年齢は有効" do
      PropCheck.forall(valid_email, valid_age) do |email, age|
        user = User.new(email: email, age: age)
        expect(user).to be_valid
      end
    end

    it "負の年齢は無効" do
      PropCheck.forall(valid_email, G.negative_integer) do |email, age|
        user = User.new(email: email, age: age)
        expect(user).not_to be_valid
        expect(user.errors[:age]).to be_present
      end
    end
  end
end
```

### サービスオブジェクトのテスト

```ruby
# app/services/price_calculator.rb
class PriceCalculator
  def initialize(base_price:, discount_rate:)
    @base_price = base_price
    @discount_rate = discount_rate
  end

  def calculate
    (@base_price * (1 - @discount_rate)).round(2)
  end
end
```

```ruby
# spec/services/price_calculator_property_spec.rb
RSpec.describe PriceCalculator do
  G = PropCheck::Generators

  # 価格ジェネレータ（0〜10000の範囲）
  let(:price_gen) { G.choose(0, 10000).map(&:to_f) }

  # 割引率ジェネレータ（0〜1の範囲）
  let(:discount_gen) { G.choose(0, 100).map { |n| n / 100.0 } }

  it "計算結果は常に0以上" do
    PropCheck.forall(price_gen, discount_gen) do |price, discount|
      result = PriceCalculator.new(base_price: price, discount_rate: discount).calculate
      expect(result).to be >= 0
    end
  end

  it "計算結果は元の価格以下" do
    PropCheck.forall(price_gen, discount_gen) do |price, discount|
      result = PriceCalculator.new(base_price: price, discount_rate: discount).calculate
      expect(result).to be <= price
    end
  end

  it "割引率0%なら価格は変わらない" do
    PropCheck.forall(price_gen) do |price|
      result = PriceCalculator.new(base_price: price, discount_rate: 0).calculate
      expect(result).to eq(price)
    end
  end
end
```

## pbtの使い方

### セットアップ

```ruby
# Gemfile
gem 'pbt', group: :test

# spec/rails_helper.rb
require 'pbt'
```

### 基本構文

```ruby
RSpec.describe "ソートのプロパティ" do
  it "ソート後は昇順になる" do
    Pbt.assert do
      Pbt.property(Pbt.array(Pbt.integer)) do |numbers|
        sorted = numbers.sort
        sorted.each_cons(2).all? { |a, b| a <= b }
      end
    end
  end
end
```

### 並行実行

pbtはRactorを使った並行実行をサポート。

```ruby
Pbt.assert(worker: :ractor) do
  Pbt.property(Pbt.array(Pbt.integer)) do |numbers|
    # 並行で実行される
    numbers.sort == numbers.sort.sort
  end
end
```

## シュリンキング（縮小）

プロパティベーステストの重要な機能の一つが**シュリンキング**だ。

テストが失敗した時、ライブラリは自動的に反例を最小化する。

```
# 失敗時の出力例
PropCheck::Failure:
  Failed after 42 tests, with shrunk input:
    numbers = [0, -1]

  Original failing input was:
    numbers = [847, -293, 1029, -1, 0, 482, -847]
```

複雑な入力ではなく、問題の本質を示す最小限の入力が得られるため、デバッグが容易になる。

## プロパティの見つけ方

プロパティベーステストを書く際のコツは、**不変条件（invariant）**を見つけること。

### よくあるプロパティパターン

| パターン | 説明 | 例 |
|---------|------|-----|
| 逆変換 | encode後にdecodeすると元に戻る | `decode(encode(x)) == x` |
| 冪等性 | 2回適用しても結果が同じ | `f(f(x)) == f(x)` |
| 順序保存 | ソート後は順序が保たれる | `sorted[i] <= sorted[i+1]` |
| サイズ保存 | 要素数が変わらない | `x.sort.length == x.length` |
| モデル比較 | 単純な実装と結果が一致 | `fast_sort(x) == naive_sort(x)` |

### Railsでの具体例

```ruby
# 逆変換: シリアライズ → デシリアライズ
PropCheck.forall(user_attributes_gen) do |attrs|
  json = UserSerializer.new(User.new(attrs)).to_json
  parsed = JSON.parse(json)
  # 必須フィールドが含まれている
  expect(parsed).to have_key("email")
end

# 冪等性: 正規化処理
PropCheck.forall(G.string) do |input|
  once = Normalizer.normalize(input)
  twice = Normalizer.normalize(once)
  expect(once).to eq(twice)
end
```

## ベストプラクティス

### 1. プロパティテストと例ベースのテストを併用する

```ruby
RSpec.describe Calculator do
  # 例ベース: 具体的なケースを確認
  it "adds 1 + 1" do
    expect(Calculator.add(1, 1)).to eq(2)
  end

  # プロパティベース: 一般的な性質を確認
  it "addition is commutative" do
    PropCheck.forall(G.integer, G.integer) do |a, b|
      Calculator.add(a, b) == Calculator.add(b, a)
    end
  end
end
```

### 2. カスタムジェネレータを作成する

```ruby
# spec/support/generators.rb
module CustomGenerators
  G = PropCheck::Generators

  def self.valid_email
    G.tuple(
      G.alphanumeric_string.where { |s| s.length > 0 },
      G.one_of(G.constant("example.com"), G.constant("test.org"))
    ).map { |local, domain| "#{local}@#{domain}" }
  end

  def self.japanese_phone_number
    G.tuple(
      G.choose(0, 99),
      G.choose(0, 9999),
      G.choose(0, 9999)
    ).map { |a, b, c| format("0%02d-%04d-%04d", a, b, c) }
  end
end
```

### 3. 失敗時のシード値を記録する

```ruby
# 失敗を再現可能にする
PropCheck.forall(G.integer, seed: 12345) do |n|
  # ...
end
```

## まとめ

| 項目 | 通常のテスト | プロパティベーステスト |
|------|-------------|---------------------|
| テストケース | 開発者が考える | 自動生成される |
| カバレッジ | 限定的 | 広範囲 |
| エッジケース | 見落としやすい | 発見しやすい |
| デバッグ | そのまま | シュリンキングで最小化 |

**プロパティベーステストは、通常のテストを置き換えるものではない。**

両者を組み合わせることで、より堅牢なテストスイートを構築できる。まずは既存のテストにプロパティテストを追加してみよう。

---

## 参考リンク

- [PropCheck GitHub](https://github.com/Qqwy/ruby-prop_check)
- [pbt GitHub](https://github.com/ohbarye/pbt)
- [PropCheck: property-based testing for your Ruby and Rails projects!](https://discuss.rubyonrails.org/t/propcheck-property-based-testing-for-your-ruby-and-rails-projects/75926)
- [RubyKaigi 2024 - Unlocking Potential of Property Based Testing with Ractor](https://rubykaigi.org/2024/)

---

この記事は [chigasaki.rb](https://crb.connpass.com/) での議論をもとに作成しました。
