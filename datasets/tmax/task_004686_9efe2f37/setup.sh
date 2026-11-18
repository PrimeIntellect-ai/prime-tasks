#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
pip3 install pytest

# Create the video fixture
mkdir -p /app
cat << 'EOF' > /tmp/subs.srt
1
00:00:01,000 --> 00:00:02,000
Route: Alpha_1 -> Beta_2 | Bytes: 1000

2
00:00:02,500 --> 00:00:03,500
Route: Beta_2 -> Gamma_3 | Bytes: 500

3
00:00:04,000 --> 00:00:05,000
Route: Alpha_1 -> Xray_9 | Bytes: 2000

4
00:00:05,500 --> 00:00:06,500
Route: Xray_9 -> Delta_2 | Bytes: 4050

5
00:00:07,000 --> 00:00:08,000
Route: Delta_2 -> Zulu_0 | Bytes: 8200

6
00:00:08,500 --> 00:00:09,500
Route: Alpha_1 -> Beta_2 | Bytes: 1500
EOF

ffmpeg -f lavfi -i color=c=blue:s=320x240:d=10 -i /tmp/subs.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/network_traffic.mp4 -y

# Setup Oracle
mkdir -p /opt/oracle
cat << 'EOF' > /opt/oracle/oracle_query_network.py
#!/usr/bin/env python3
import sys
import json
import sqlite3

def run(node_id):
    conn = sqlite3.connect('/opt/oracle/network.db')
    cur = conn.cursor()

    query = """
    WITH RECURSIVE
    paths(target, level, edge_bytes) AS (
        SELECT target, 1, bytes FROM edges WHERE source = ?
        UNION ALL
        SELECT e.target, p.level + 1, e.bytes
        FROM edges e
        JOIN paths p ON e.source = p.target
    ),
    min_levels AS (
        SELECT target, MIN(level) as min_lvl FROM paths GROUP BY target
    ),
    filtered_paths AS (
        SELECT p.target, p.level, MAX(p.edge_bytes) as max_bytes
        FROM paths p
        JOIN min_levels m ON p.target = m.target AND p.level = m.min_lvl
        GROUP BY p.target, p.level
    )
    SELECT level, MAX(max_bytes) as level_max, SUM(max_bytes) OVER () as total_bytes
    FROM filtered_paths
    GROUP BY level
    """
    cur.execute(query, (node_id,))
    rows = cur.fetchall()

    if not rows:
        print(json.dumps({"start_node": node_id, "total_descendant_bytes": 0, "max_bytes_per_level": {}}))
        return

    cur.execute("""
    WITH RECURSIVE
    nodes(node) AS (
        SELECT ?
        UNION
        SELECT e.target FROM edges e JOIN nodes n ON e.source = n.node
    )
    SELECT SUM(bytes) FROM edges WHERE source IN nodes
    """, (node_id,))
    total_descendant_bytes = cur.fetchone()[0] or 0

    max_bytes_per_level = {}
    for r in rows:
        max_bytes_per_level[str(r[0])] = r[1]

    res = {
        "start_node": node_id,
        "total_descendant_bytes": total_descendant_bytes,
        "max_bytes_per_level": max_bytes_per_level
    }
    print(json.dumps(res))

if __name__ == '__main__':
    if len(sys.argv) > 1:
        run(sys.argv[1])
EOF
chmod +x /opt/oracle/oracle_query_network.py

# Create Oracle Database
python3 -c "
import sqlite3
import os

os.makedirs('/opt/oracle', exist_ok=True)
conn = sqlite3.connect('/opt/oracle/network.db')
cur = conn.cursor()
cur.execute('CREATE TABLE edges (source TEXT, target TEXT, bytes INTEGER)')
edges = [
    ('Alpha_1', 'Beta_2', 2500),
    ('Beta_2', 'Gamma_3', 500),
    ('Alpha_1', 'Xray_9', 2000),
    ('Xray_9', 'Delta_2', 4050),
    ('Delta_2', 'Zulu_0', 8200)
]
cur.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
