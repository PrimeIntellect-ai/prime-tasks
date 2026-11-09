#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json

# Create SQLite DB
conn = sqlite3.connect('/home/user/data/authors.db')
c = conn.cursor()
c.execute('CREATE TABLE authors (author_id TEXT, name TEXT, institution TEXT)')
authors = [
    ('A1', 'Alice', 'MIT'),
    ('A2', 'Bob', 'Stanford'),
    ('A3', 'Charlie', 'UCB'),
    ('A4', 'David', 'CMU')
]
c.executemany('INSERT INTO authors VALUES (?, ?, ?)', authors)
conn.commit()
conn.close()

# Create JSONL Papers
papers = [
    {"paper_id": "P01", "title": "Graph DBs 101", "authors": ["A1", "A2"], "citations": ["P02", "P03", "P99"]},
    {"paper_id": "P02", "title": "Graph DBs 102", "authors": ["A1", "A3"], "citations": ["P03", "P04"]},
    {"paper_id": "P03", "title": "Graph DBs 103", "authors": ["A1", "A4"], "citations": ["P01", "P99"]},
    {"paper_id": "P04", "title": "Unrelated Work", "authors": ["A2", "A3"], "citations": ["P01"]},
    {"paper_id": "P99", "title": "The Masterpiece", "authors": ["A4"], "citations": []}
]
with open('/home/user/data/papers.jsonl', 'w') as f:
    for p in papers:
        f.write(json.dumps(p) + '\n')
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
