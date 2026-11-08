#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    useradd -m -s /bin/bash user || true

    # Create the legacy docs file with Windows-1252 encoding
    python3 -c '
import json
data = [
    {"id": "art1", "title": "Setup Guide", "body": "Café configuration...", "tags": ["setup", "config"]}
]
with open("/home/user/legacy_docs.json", "w", encoding="windows-1252") as f:
    json.dump(data, f, ensure_ascii=False)
'

    # Create vendored package
    mkdir -p /app/vendor/pydocorg-1.2.0/pydocorg

    cat << 'EOF' > /app/vendor/pydocorg-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name="pydocorg",
    version="1.2.0",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "pydocorg=pydocorg.cli:main"
        ]
    }
)
EOF

    cat << 'EOF' > /app/vendor/pydocorg-1.2.0/pydocorg/__init__.py
EOF

    cat << 'EOF' > /app/vendor/pydocorg-1.2.0/pydocorg/cli.py
import argparse
import json
import os
from .linker import create_symlinks

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command")
    parser.add_argument("--input")
    parser.add_argument("--output")
    args = parser.parse_args()

    if args.command == "build":
        with open(args.input, "r", encoding="utf-8") as f:
            data = json.load(f)

        articles_dir = os.path.join(args.output, "articles")
        tags_dir = os.path.join(args.output, "tags")
        os.makedirs(articles_dir, exist_ok=True)
        os.makedirs(tags_dir, exist_ok=True)

        for article in data:
            filename = f"{article['id']}.md"
            filepath = os.path.join(articles_dir, filename)
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(f"# {article['title']}\n\n{article['body']}")
            create_symlinks(article, tags_dir, filename)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/vendor/pydocorg-1.2.0/pydocorg/linker.py
import os

def create_symlinks(article, tags_dir, article_filename):
    for tag in article.get("tags", []):
        tag_dir = os.path.join(tags_dir, tag)
        os.makedirs(tag_dir, exist_ok=True)
        link_path = os.path.join(tag_dir, article_filename)
        # BUG: Missing the correct upward directory traversal
        target_path = f"../articles/{article_filename}"
        if not os.path.exists(link_path):
            os.symlink(target_path, link_path)
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
