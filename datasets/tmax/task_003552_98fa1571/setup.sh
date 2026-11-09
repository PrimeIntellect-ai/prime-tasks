#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

os.makedirs('/home/user', exist_ok=True)

db_path = '/home/user/research_data.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)")
cursor.execute("CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER)")
cursor.execute("CREATE TABLE citations (source_id INTEGER, target_id INTEGER)")
cursor.execute("CREATE TABLE author_impact_cache (author_name TEXT, impact_score INTEGER)")

authors = [(1, 'Alice Smith'), (2, 'Bob Jones'), (3, 'Charlie Brown'), (4, 'Diana Prince')]
cursor.executemany("INSERT INTO authors VALUES (?, ?)", authors)

papers = [
    (101, 'Deep Learning Basics', 1),
    (102, 'Advanced Neural Nets', 2),
    (103, 'Graph Databases', 3),
    (104, 'Data Mining', 4),
    (105, 'AI Ethics', 1)
]
cursor.executemany("INSERT INTO papers VALUES (?, ?, ?)", papers)

citations = [
    (102, 101), (103, 101), (104, 101),
    (103, 105), (104, 105),
    (101, 102), (104, 102),
    (101, 104)
]
cursor.executemany("INSERT INTO citations VALUES (?, ?)", citations)

stale_cache = [
    ('Alice Smith', 999),
    ('Bob Jones', 50),
    ('Charlie Brown', 5000)
]
cursor.executemany("INSERT INTO author_impact_cache VALUES (?, ?)", stale_cache)

conn.commit()
conn.close()

schema = {
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "top_authors": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "impact_score": { "type": "integer" }
        },
        "required": ["name", "impact_score"]
      },
      "minItems": 3,
      "maxItems": 3
    }
  },
  "required": ["top_authors"]
}

with open('/home/user/schema.json', 'w') as f:
    json.dump(schema, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
