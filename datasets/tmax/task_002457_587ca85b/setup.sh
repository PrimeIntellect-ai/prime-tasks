#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    python3 -c "
import sqlite3
import os

db_path = '/home/user/graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create obfuscated tables
c.execute('CREATE TABLE t_n (c_id INTEGER PRIMARY KEY, c_lbl TEXT)')
c.execute('CREATE TABLE t_e (c_src INTEGER, c_dst INTEGER)')

# Create the corrupted index first
c.execute('CREATE INDEX idx_edge_src ON t_e(c_src)')

nodes = [
    (1, 'Core_Root'),
    (2, 'Node_A'),
    (3, 'Node_B'),
    (4, 'Node_C'),
    (5, 'Sub_Hub_Alpha'),
    (6, 'Node_D'),
    (7, 'Node_E'),
    (8, 'Node_F'),
    (9, 'Node_G'),
    (10, 'Outsider_Hub'),
    (11, 'Out_1'),
    (12, 'Out_2'),
    (13, 'Out_3'),
    (14, 'Out_4'),
    (15, 'Out_5')
]

edges = [
    (1, 2), (1, 3), 
    (2, 4), (2, 5), 
    (5, 6), (5, 7), (5, 8), (5, 9), 
    (3, 7),
    (10, 11), (10, 12), (10, 13), (10, 14), (10, 15)
]

c.executemany('INSERT INTO t_n VALUES (?, ?)', nodes)
c.executemany('INSERT INTO t_e VALUES (?, ?)', edges)
conn.commit()
conn.close()
"

    chmod -R 777 /home/user
