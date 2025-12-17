---
title: "accepts_nested_attributes_forを使わない責務分割とデータ構造"
emoji: "🏗️"
type: "tech"
topics: ["rails", "ruby", "architecture", "design-patterns"]
published: true
---

「`accepts_nested_attributes_for` は絶対に使うべきではない」と言い切ってしまうと困る人が出る。だから、なぜそう考えるのか、どういうパターンがあるのか、データ構造の違いは何を意味するのかを整理しておく。

## 問題の所在：Model / View / Controller の責務分割

`accepts_nested_attributes_for` を使いたくなる場面は、たいてい「フォームから複数のモデルを一度に保存したい」ときだ。例えば、`Order` と `OrderItem` を同時に作る、`User` と `Profile` を同時に更新する、といったケース。

```ruby
# これを避けたい典型例
class Order < ApplicationRecord
  has_many :items
  accepts_nested_attributes_for :items
end
```

この機能を使うと、コントローラーは薄く書ける。フォームから来たパラメータをそのまま `order.update(params)` に流せば、関連モデルも一緒に保存される。しかし、ここには構造的な問題が埋まっている。

**モデルが「フォームの構造」を知ってしまう。**

本来、モデルはビジネスロジックとデータの整合性を守る場所であり、「外から来るデータがどういう形をしているか」を知る必要はない。それはコントローラーやフォームオブジェクトが担うべき責務だ。`accepts_nested_attributes_for` を使うと、この境界が壊れる。

## パターン1：ネストした構造 `{ a: { b: } }`

`accepts_nested_attributes_for` を使う場合、パラメータは次のような形になる。

```ruby
{
  order: {
    customer_name: "田中太郎",
    items_attributes: [
      { product_id: 1, quantity: 2 },
      { product_id: 3, quantity: 1 }
    ]
  }
}
```

この構造の問題点：

### 1. モデルが内部構造を公開する

`items_attributes` という名前は、`Order` モデルが「ネストされた属性を受け取る」という実装の詳細を外部に公開している。フォーム側は `_attributes` という接尾辞を意識しなければならない。

### 2. バリデーションの複雑化

`Order` のバリデーションと `Item` のバリデーションが絡み合う。`items_attributes` 経由で作られた `Item` が不正だった場合、エラーメッセージの組み立てが煩雑になる。

```ruby
# こういうエラーハンドリングになりがち
order.errors.full_messages
# => ["Items product 商品を入力してください"]
```

### 3. テストが難しい

モデル単体のテストでは、`items_attributes` というフォーム由来のパラメータ構造を再現しなければならない。ビジネスロジックのテストに、フォームの知識が必要になる。

### 4. 変更に弱い

フォームの構造が変わると、モデル側の `accepts_nested_attributes_for` の設定も変える必要がある。`allow_destroy`、`reject_if` などのオプションがモデルに散らばり、「どこで何を許可しているか」が見えにくくなる。

## パターン2：フラットな構造 `{ a:, b: }`

`accepts_nested_attributes_for` を使わず、コントローラーまたはフォームオブジェクトで組み立てる場合、パラメータは次のような形になる。

```ruby
{
  order: {
    customer_name: "田中太郎"
  },
  items: [
    { product_id: 1, quantity: 2 },
    { product_id: 3, quantity: 1 }
  ]
}
```

この構造の利点：

### 1. 責務が分離される

コントローラーまたはフォームオブジェクトが「外から来たデータを解釈し、モデルに渡す形に整える」責務を持つ。モデルは「受け取ったデータを保存し、整合性を守る」責務に集中できる。

```ruby
class OrdersController < ApplicationController
  def create
    order = Order.new(order_params)

    items_params.each do |item_param|
      order.items.build(item_param)
    end

    if order.save
      redirect_to order
    else
      render :new
    end
  end

  private

  def order_params
    params.require(:order).permit(:customer_name)
  end

  def items_params
    params.require(:items).map do |item|
      item.permit(:product_id, :quantity)
    end
  end
end
```

### 2. テストが書きやすい

モデルのテストは純粋にビジネスロジックだけをテストできる。フォームの構造を意識する必要がない。

```ruby
# モデルのテスト
order = Order.new(customer_name: "田中太郎")
order.items.build(product_id: 1, quantity: 2)
expect(order).to be_valid
```

コントローラーやフォームオブジェクトのテストは、「パラメータの変換」に集中できる。

### 3. バリデーションが明確

`Order` のバリデーションと `Item` のバリデーションが分離される。エラーハンドリングも素直に書ける。

```ruby
if order.invalid?
  order.errors.full_messages # Order 自身のエラー
end

if order.items.any?(&:invalid?)
  order.items.flat_map { |item| item.errors.full_messages } # Item のエラー
end
```

### 4. 変更に強い

フォームの構造が変わっても、コントローラーやフォームオブジェクトだけを変えればいい。モデルは影響を受けない。

## フォームオブジェクトでさらに整理する

フラットな構造を採用すると、コントローラーがやや複雑になる。そこで、フォームオブジェクトを導入する。

```ruby
class OrderForm
  include ActiveModel::Model

  attr_accessor :customer_name, :items

  validates :customer_name, presence: true
  validate :items_must_be_valid

  def save
    return false if invalid?

    ActiveRecord::Base.transaction do
      order = Order.create!(customer_name: customer_name)
      items.each do |item_attrs|
        order.items.create!(item_attrs)
      end
      order
    end
  end

  private

  def items_must_be_valid
    items.each_with_index do |item_attrs, index|
      item = OrderItem.new(item_attrs)
      if item.invalid?
        item.errors.each do |error|
          errors.add(:"items[#{index}].#{error.attribute}", error.message)
        end
      end
    end
  end
end
```

コントローラーは次のように薄くなる。

```ruby
class OrdersController < ApplicationController
  def create
    form = OrderForm.new(order_form_params)

    if form.save
      redirect_to order
    else
      render :new
    end
  end

  private

  def order_form_params
    params.require(:order_form).permit(:customer_name, items: [:product_id, :quantity])
  end
end
```

フォームオブジェクトが「外部とモデルの境界」を担い、コントローラーとモデルの両方が薄く保たれる。

## どちらが優れているか

`{ a: { b: } }` のネスト構造は、短期的には便利に見える。コードが少なく、Rails の機能をそのまま使える。しかし、変更に弱く、テストが難しく、責務が混ざる。

`{ a:, b: }` のフラット構造は、初期コストは若干高い。コントローラーやフォームオブジェクトを書く必要がある。しかし、変更に強く、テストが書きやすく、責務が明確になる。

**長期的なメンテナンス性を考えれば、フラット構造の方が圧倒的に優れている。**

## まとめ

`accepts_nested_attributes_for` を使いたくなったら、それは「責務分割が失敗しているサイン」だと考える。モデルはビジネスロジックに集中し、フォームの構造やパラメータの変換はコントローラーやフォームオブジェクトに任せる。

データ構造は単なる形の問題ではなく、責務の配置を表している。ネストした構造は依存を深くし、フラットな構造は境界を明確にする。Rails の便利な機能に頼りすぎず、正しい責務分割を優先する。そうすれば、コードは呼吸しやすくなる。
