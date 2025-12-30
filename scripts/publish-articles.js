#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { globSync } = require('glob');

const ARTICLES_DIR = path.join(__dirname, '../articles');

function publishUnpublishedArticles() {
  const articleFiles = globSync(`${ARTICLES_DIR}/*.md`);
  const updatedFiles = [];

  articleFiles.forEach((file) => {
    const content = fs.readFileSync(file, 'utf-8');
    
    // published: false を探す
    if (/^published:\s*false/m.test(content)) {
      const updatedContent = content.replace(
        /^published:\s*false/m,
        'published: true'
      );
      
      fs.writeFileSync(file, updatedContent, 'utf-8');
      updatedFiles.push(path.basename(file));
      console.log(`✅ Published: ${path.basename(file)}`);
    }
  });

  if (updatedFiles.length === 0) {
    console.log('ℹ️  No unpublished articles found.');
  } else {
    console.log(`\n🎉 Total ${updatedFiles.length} article(s) published.`);
  }

  return updatedFiles;
}

if (require.main === module) {
  publishUnpublishedArticles();
}

module.exports = { publishUnpublishedArticles };
