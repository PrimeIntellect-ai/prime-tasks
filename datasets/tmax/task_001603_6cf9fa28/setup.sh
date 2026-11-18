#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis

    mkdir -p /app/data

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

def setup():
    conn = sqlite3.connect('/app/data/graph.db')
    cur = conn.cursor()

    cur.execute("CREATE TABLE nodes(id INTEGER PRIMARY KEY, name TEXT, score REAL, active INTEGER)")
    cur.execute("CREATE TABLE edges(src INTEGER, dst INTEGER)")

    for i in range(1, 101):
        cur.execute("INSERT INTO nodes VALUES (?, ?, ?, ?)", (i, f"User{i}", i*0.1, 1))

    for i in range(1, 101):
        for j in range(1, 101):
            if i != j and (i+j)%2 == 0:
                cur.execute("INSERT INTO edges VALUES (?, ?)", (i, j))

    cur.execute("CREATE INDEX idx_edges_src ON edges(src)")
    conn.commit()

    cur.execute("SELECT rootpage FROM sqlite_master WHERE name='idx_edges_src'")
    rootpage = cur.fetchone()[0]

    cur.execute("PRAGMA writable_schema = ON")
    cur.execute("DELETE FROM sqlite_master WHERE name='idx_edges_src'")
    conn.commit()

    cur.execute("DELETE FROM edges WHERE src % 3 = 0")
    conn.commit()

    cur.execute("PRAGMA writable_schema = ON")
    cur.execute("INSERT INTO sqlite_master (type, name, tbl_name, rootpage, sql) VALUES ('index', 'idx_edges_src', 'edges', ?, 'CREATE INDEX idx_edges_src ON edges(src)')", (rootpage,))
    conn.commit()

    conn.close()

if __name__ == "__main__":
    setup()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    cat << 'EOF' > /app/oracle.py
import sys
import json
import sqlite3
import redis

def main():
    node_id = int(sys.argv[1])
    limit = int(sys.argv[2])
    offset = int(sys.argv[3])

    r = redis.Redis(host='127.0.0.1', port=6379, db=0, decode_responses=True)
    key = f"graph:{node_id}:{limit}:{offset}"

    cached = r.get(key)
    if cached:
        print(cached)
        return

    conn = sqlite3.connect('/app/data/graph.db')
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    query = """
        SELECT n.id, n.name, n.score 
        FROM edges e NOT INDEXED
        JOIN nodes n ON e.dst = n.id
        WHERE e.src = ? AND n.active = 1
        ORDER BY n.score DESC, n.id ASC
        LIMIT ? OFFSET ?
    """
    cur.execute(query, (node_id, limit, offset))
    rows = cur.fetchall()

    res = [{"id": row["id"], "name": row["name"], "score": row["score"]} for row in rows]
    json_out = json.dumps(res, separators=(',', ':'))

    r.set(key, json_out)
    print(json_out)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
