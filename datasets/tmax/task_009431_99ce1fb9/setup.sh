#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > init_db.py
import sqlite3

conn = sqlite3.connect('graph.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id TEXT PRIMARY KEY, weight INTEGER)')
c.execute('CREATE TABLE edges (source TEXT, target TEXT)')

# Insert nodes
nodes = [('ROOT', 10), ('A', 20), ('B', 30), ('C', 40), ('D', 50), ('E', 60)]
c.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)

# Insert edges
edges = [('ROOT', 'A'), ('ROOT', 'B'), ('A', 'C'), ('B', 'D'), ('D', 'E')]
c.executemany('INSERT INTO edges VALUES (?, ?)', edges)

conn.commit()
conn.close()
EOF

python3 init_db.py
rm init_db.py

cat << 'EOF' > concurrent_update.py
import sqlite3
import threading

def update_nodes(nodes_to_update, added_weight):
    # Buggy: deadlocks due to inconsistent lock order and uses string concatenation
    conn = sqlite3.connect('graph.db', timeout=1)
    try:
        c = conn.cursor()
        c.execute("BEGIN TRANSACTION")
        for node in nodes_to_update:
            # VULNERABLE AND DEADLOCK-PRONE
            c.execute(f"UPDATE nodes SET weight = weight + {added_weight} WHERE id = '{node}'")
        conn.commit()
    except sqlite3.Error as e:
        print(f"Error: {e}")
        conn.rollback()
    finally:
        conn.close()

# Two threads updating overlapping nodes in reverse order -> Deadlock
t1 = threading.Thread(target=update_nodes, args=(['A', 'B', 'C', 'D'], 5))
t2 = threading.Thread(target=update_nodes, args=(['D', 'C', 'B', 'A'], 10))

t1.start()
t2.start()

t1.join()
t2.join()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
