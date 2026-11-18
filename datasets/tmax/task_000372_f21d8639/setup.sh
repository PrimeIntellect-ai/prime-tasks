#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak sqlite3
    pip3 install pytest

    mkdir -p /app/data
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the audio briefing
    espeak -w /app/briefing.wav "Hello. The main database has a corrupted index named 'idx_stale_cache'. Please drop it before running your window functions. For the classifier, an adversarial graph is defined as any network where at least one node has a out-degree of five or more, but an in-degree of exactly zero. Everything else is clean."

    # Create the database and corpora
    python3 -c "
import sqlite3
import os

conn = sqlite3.connect('/app/data/network.db')
c = conn.cursor()
c.execute('CREATE TABLE transactions (tx_id INTEGER, sender TEXT, receiver TEXT, amount REAL, timestamp INTEGER)')
c.execute('CREATE INDEX idx_stale_cache ON transactions (sender, receiver)')
c.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', [
    (1, 'A', 'B', 100.0, 1000),
    (2, 'A', 'C', 50.0, 1001),
    (3, 'B', 'C', 20.0, 1002),
    (4, 'C', 'A', 10.0, 1003)
])
conn.commit()
conn.close()

# Clean graph: A has out-degree 4, in-degree 1
with open('/app/corpora/clean/graph1.csv', 'w') as f:
    f.write('source,target,amount\nA,B,10\nA,C,10\nA,D,10\nA,E,10\nB,A,10\n')

# Evil graph: A has out-degree 5, in-degree 0
with open('/app/corpora/evil/graph1.csv', 'w') as f:
    f.write('source,target,amount\nA,B,10\nA,C,10\nA,D,10\nA,E,10\nA,F,10\nB,C,10\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
