#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    mkdir -p /home/user
    cd /home/user

    python3 -c '
import sqlite3

conn = sqlite3.connect("logistics.db")
c = conn.cursor()

# Nodes
c.execute("CREATE TABLE t1_x (id INTEGER PRIMARY KEY, name TEXT, region_code TEXT)")
nodes = [
    (1, "Warehouse_Alpha", "REG_1"),
    (2, "Hub_Beta", "REG_1"),
    (3, "Central_Sort", "REG_2"),
    (4, "Depot_Gamma", "REG_3"),
    (5, "Station_Delta", "REG_3")
]
c.executemany("INSERT INTO t1_x VALUES (?, ?, ?)", nodes)

# Edges
c.execute("CREATE TABLE t2_y (source_id INTEGER, target_id INTEGER, distance REAL)")
edges = [
    (1, 2, 50.0),
    (1, 3, 120.0),
    (2, 3, 150.0),
    (3, 4, 110.0),
    (3, 5, 80.0),
    (4, 5, 60.0)
]
c.executemany("INSERT INTO t2_y VALUES (?, ?, ?)", edges)
# Add reverse edges for bidirectionality just in case
c.executemany("INSERT INTO t2_y VALUES (?, ?, ?)", [(t, s, d) for s, t, d in edges])

# Deliveries
c.execute("CREATE TABLE t3_z (delivery_id INTEGER PRIMARY KEY, src_id INTEGER, dst_id INTEGER, cost REAL)")
deliveries = [
    (101, 1, 3, 500.0),
    (102, 1, 3, 450.0),
    (103, 1, 2, 900.0),
    (104, 2, 3, 600.0),
    (105, 3, 4, 700.0),
    (106, 3, 4, 750.0),
    (107, 3, 4, 800.0)
]
c.executemany("INSERT INTO t3_z VALUES (?, ?, ?, ?)", deliveries)

conn.commit()
conn.close()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
