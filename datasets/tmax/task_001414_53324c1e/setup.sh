#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/dataset
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/dataset/setup.py
import sqlite3
import json

db_path = '/home/user/dataset/papers.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER)')
c.execute('CREATE TABLE citations_raw (source_id INTEGER, target_id INTEGER, is_valid INTEGER)')

# Insert papers
for i in range(1, 15):
    c.execute('INSERT INTO papers (id, title, year) VALUES (?, ?, ?)', (i, f'Paper {i}', 2020))

# Valid DB citations
db_citations = [
    (1, 2, 1),
    (2, 3, 1),
    (3, 4, 1),
    (8, 9, 1),
    (9, 10, 1)
]

# Invalid DB citations (Stale) - forms a longer path if mistakenly included
stale_citations = [
    (4, 11, 0),
    (11, 12, 0),
    (12, 13, 0),
    (13, 14, 0)
]

for src, tgt, val in db_citations + stale_citations:
    c.execute('INSERT INTO citations_raw (source_id, target_id, is_valid) VALUES (?, ?, ?)', (src, tgt, val))

conn.commit()
conn.close()

# JSONL updates
with open('/home/user/dataset/updates.jsonl', 'w') as f:
    f.write(json.dumps({"paper_id": 4, "missing_citations": [5]}) + '\n')
    f.write(json.dumps({"paper_id": 5, "missing_citations": [6]}) + '\n')
    f.write(json.dumps({"paper_id": 6, "missing_citations": [7]}) + '\n')
    f.write(json.dumps({"paper_id": 8, "missing_citations": [3]}) + '\n')
EOF

    python3 /home/user/dataset/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
