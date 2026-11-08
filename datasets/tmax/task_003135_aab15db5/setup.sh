#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/research_data.db')
c = conn.cursor()

c.execute('''CREATE TABLE taxonomy (id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT)''')
c.execute('''CREATE TABLE papers (id INTEGER PRIMARY KEY, topic_id INTEGER, title TEXT, citations INTEGER)''')

taxonomy_data = [
    (1, None, 'Computer Science'),
    (2, 1, 'Artificial Intelligence'),
    (3, 2, 'Machine Learning'),
    (4, 2, 'Natural Language Processing'),
    (5, 1, 'Databases'),
    (6, 3, 'Deep Learning')
]
c.executemany('INSERT INTO taxonomy VALUES (?,?,?)', taxonomy_data)

papers_data = [
    (1, 3, 'Intro to ML', 150),
    (2, 3, 'Advanced ML', 200),
    (3, 4, 'Word Embeddings', 50),
    (4, 4, 'Attention Mechanisms', 300),
    (5, 6, 'CNNs', 1000),
    (6, 6, 'Transformers', 900),
    (7, 5, 'SQL Tuning', 400),
    (8, 2, 'General AI History', 80)
]
c.executemany('INSERT INTO papers VALUES (?,?,?,?)', papers_data)

conn.commit()
conn.close()
EOF
    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
