---
title: "伝言ゲームが組織とコードを狂わせる"
tags: ["communication", "architecture"]
date: "2025-12-26T05:40:30+09:00"
draft: false
---

組織もプログラミングのソースコードも、余計な伝言ゲームが積み重なると途端におかしくなる。意図は歪み、設計は継ぎ足され続け、どこで本質を見失ったのか誰にも分からなくなる。

## 伝言ゲームが生まれる条件
### 組織の断絶
- 担当レイヤーが細切れで、意思決定の度に人をまたぐ。
- 受け取った内容を記録せず、個人の感触だけで次へ渡す。
- フィードバックが遅れ、誤解が固まってから発覚する。

### コードの断絶
- 関数引数をとにかく渡し続け、誰が責任を持つのか曖昧になる。
- 状態をグローバルに共有し、副作用の出所が見えなくなる。
- 仕様が条件分岐に散らばり、意図を一目で確認できない。

## GOOD / BADで見る流れの作り方
### GOOD: コンストラクタで依存を抱きとめる
```ruby
class TaxCalculator
  def initialize(rate: 1.1)
    @rate = rate
  end

  def call(amount)
    (amount * @rate).round(2)
  end
end

class Invoice
  def initialize(amount:, tax_calculator: TaxCalculator.new)
    @amount = amount
    @tax_calculator = tax_calculator
  end

  def issue
    total = @tax_calculator.call(@amount)
    "Total: #{total}"
  end
end

invoice = Invoice.new(amount: 1200)
puts invoice.issue
```
値は入り口（コンストラクタ）で受け止め、後続では責務を分担した協調だけを行う。依存の方向は一方通行で、副作用も限定される。

### BAD: クラスメソッドで引数をバケツリレー
```ruby
class LegacyReport
  def self.build(user_id, region, locale, timezone, currency, format)
    base = fetch_base(user_id, region, locale, timezone)
    enrich(base, currency, format)
  end

  def self.fetch_base(user_id, region, locale, timezone)
    query_database(user_id, region, locale, timezone, cache: true, verbose: false)
  end

  def self.query_database(user_id, region, locale, timezone, cache:, verbose:)
    # どこで値が変わったのか分からない迷路
    "..."
  end

  def self.enrich(base, currency, format)
    "#{base} (#{currency}) in #{format}"
  end
end
```
入口が定まらず、呼ばれるたびに引数を足すしかなくなる。誰の責務か分からないまま依存が滲み出て、変更点を洗い出すのも困難だ。

## 人の伝言ゲームのGOOD / BAD
### GOOD: 一直線に伝える
- 当事者同士が話し、要点をメモとともに共有する。
- 理解を確認するリキャップを挟み、解釈のズレを即座に潰す。
- 誰が次のアクションを取るのか、その場で合意しておく。

### BAD: ぐるぐる回す
- 中継役が増え、推測や感情が混ざる。
- 伝える内容が定義されず、各人が好きな順序と粒度で渡す。
- 元の意図に立ち返る手段がなく、最後に気付いた齟齬を戻せない。

## シンプルに戻すチェックリスト
- 入口と出口を固定し、中間の橋渡しを減らせているか。
- 役割ごとに責務を閉じ込め、誰が何を保証するか明文化したか。
- 情報が一方向に流れ、巻き戻しが必要な箇所を消せているか。
- 「なぜこの引数が必要か？」と問われたときに即答できるか。

## 声を揃える
必要な人へ必要なメッセージを最短距離で届ける。その原則を守れたとき、組織もコードも余計な伝言ゲームから解放される。流れを一度整理し、誰が見ても同じ構造に見える状態を保とう。
