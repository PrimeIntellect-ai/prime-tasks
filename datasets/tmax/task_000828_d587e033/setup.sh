#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest gTTS pydub networkx scipy SpeechRecognition

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import random
import networkx as nx
import json
from gtts import gTTS
from pydub import AudioSegment

# Generate Audio
text = "Warning, critical corruption detected in the backup. Do not restore data from shard ID seven, shard ID twenty-three, and shard ID fifty-one."
tts = gTTS(text)
tts.save("/tmp/temp.mp3")
audio = AudioSegment.from_mp3("/tmp/temp.mp3")
audio.export("/app/incident_report.wav", format="wav")

# Generate DB
conn = sqlite3.connect('/app/backup.db')
c = conn.cursor()
c.execute('''CREATE TABLE entities (id VARCHAR, entity_type VARCHAR, shard_id INT)''')
c.execute('''CREATE TABLE relations (src VARCHAR, dst VARCHAR, rel_type VARCHAR, weight FLOAT, shard_id INT)''')

random.seed(42)
nodes = [f"node_{i}" for i in range(500)]
for n in nodes:
    shard = random.randint(1, 100)
    c.execute("INSERT INTO entities VALUES (?, ?, ?)", (n, "typeA", shard))

edges = []
for _ in range(2000):
    src = random.choice(nodes)
    dst = random.choice(nodes)
    weight = random.uniform(0.1, 2.0)
    shard = random.randint(1, 100)
    edges.append((src, dst, weight, shard))
    c.execute("INSERT INTO relations VALUES (?, ?, ?, ?, ?)", (src, dst, "relA", weight, shard))

conn.commit()

# Ground truth calculation
corrupted = {7, 23, 51}
c.execute("SELECT id FROM entities WHERE shard_id NOT IN (7, 23, 51)")
valid_nodes = set(row[0] for row in c.fetchall())

c.execute("""
    SELECT src, dst, weight 
    FROM relations 
    WHERE shard_id NOT IN (7, 23, 51)
""")
valid_edges = []
for src, dst, weight in c.fetchall():
    if src in valid_nodes and dst in valid_nodes:
        valid_edges.append((src, dst, weight))

G = nx.DiGraph()
G.add_nodes_from(valid_nodes)
for src, dst, weight in valid_edges:
    G.add_edge(src, dst, weight=weight)

pr = nx.pagerank(G, alpha=0.85, weight='weight')

with open('/app/ground_truth.json', 'w') as f:
    json.dump(pr, f)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
