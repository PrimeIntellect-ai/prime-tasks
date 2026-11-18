#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest networkx gtts

mkdir -p /app
mkdir -p /home/user

# Create the database
python3 << 'EOF'
import sqlite3
import random

conn = sqlite3.connect('/app/microservices.db')
c = conn.cursor()
c.execute('CREATE TABLE services(id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE dependencies(source INTEGER, target INTEGER, latency INTEGER)')

for i in range(1, 101):
    c.execute('INSERT INTO services(id, name) VALUES (?, ?)', (i, f'service_{i}'))

edges = set()
while len(edges) < 500:
    src = random.randint(1, 100)
    tgt = random.randint(1, 100)
    if src != tgt:
        edges.add((src, tgt))

for src, tgt in edges:
    latency = random.randint(10, 100)
    c.execute('INSERT INTO dependencies(source, target, latency) VALUES (?, ?, ?)', (src, tgt, latency))

c.execute('CREATE INDEX idx_stale_backup ON dependencies(source)')

conn.commit()
conn.close()
EOF

# Create the audio file
python3 << 'EOF'
from gtts import gTTS
text = "Warning. The index idx_stale_backup on the dependencies table is corrupted. Please drop it before querying."
tts = gTTS(text)
tts.save('/app/incident_voicemail.wav')
EOF

# Create the oracle
cat << 'EOF' > /app/oracle_path.py
import sys
import sqlite3
import networkx as nx

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    src = int(sys.argv[1])
    tgt = int(sys.argv[2])

    conn = sqlite3.connect('/app/microservices.db')
    c = conn.cursor()
    c.execute('DROP INDEX IF EXISTS idx_stale_backup')
    c.execute('SELECT source, target, latency FROM dependencies')
    rows = c.fetchall()
    conn.close()

    G = nx.DiGraph()
    for u, v, w in rows:
        G.add_edge(u, v, weight=w)

    try:
        path_length = nx.shortest_path_length(G, source=src, target=tgt, weight='weight')
        print(path_length)
    except nx.NetworkXNoPath:
        print("-1")
    except nx.NodeNotFound:
        print("-1")

if __name__ == '__main__':
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
