#!/bin/bash

# Zenn の記事を Hugo 形式に変換するスクリプト

ARTICLES_DIR="articles"
HUGO_POSTS_DIR="hugo-site/content/posts"

# 出力先ディレクトリが存在しない場合は作成
mkdir -p "$HUGO_POSTS_DIR"

# published: true の記事のみを処理
for file in "$ARTICLES_DIR"/*.md; do
  filename=$(basename "$file")
  
  # .keep ファイルはスキップ
  if [ "$filename" = ".keep" ]; then
    continue
  fi
  
  # published: true の記事のみ処理
  if grep -q "published: true" "$file"; then
    echo "Converting: $filename"
    
    # Hugo 用のディレクトリを作成
    slug="${filename%.md}"
    output_dir="$HUGO_POSTS_DIR/$slug"
    mkdir -p "$output_dir"
    
    # 一時ファイルを作成
    temp_file=$(mktemp)
    
    # 現在の日付を取得
    current_date=$(date -u +"%Y-%m-%dT%H:%M:%S+09:00")
    
    # Front matter の変換
    awk -v date="$current_date" '
    BEGIN { in_frontmatter=0; print "---" }
    /^---$/ {
      if (NR==1) { in_frontmatter=1; next }
      if (in_frontmatter) { in_frontmatter=0; print "date: \"" date "\""; print "draft: false"; print "---"; next }
    }
    in_frontmatter {
      if (/^title:/) { print; next }
      if (/^emoji:/) { next }
      if (/^type:/) { next }
      if (/^topics:/) {
        gsub(/topics:/, "tags:")
        print
        next
      }
      if (/^published:/) { next }
    }
    !in_frontmatter { print }
    ' "$file" > "$temp_file"
    
    # 出力ファイルに書き込み
    mv "$temp_file" "$output_dir/index.md"
    
    echo "✓ Converted to: $output_dir/index.md"
  else
    echo "Skipping (not published): $filename"
  fi
done

echo ""
echo "Conversion complete!"
echo "Published articles are now in: $HUGO_POSTS_DIR"
