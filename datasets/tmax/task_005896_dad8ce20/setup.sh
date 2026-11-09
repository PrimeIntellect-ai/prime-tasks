#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/db_backups

    python3 -c "
import sqlite3
import os

os.makedirs('/home/user/db_backups', exist_ok=True)

# Primary metrics DB
conn1 = sqlite3.connect('/home/user/db_backups/primary_metrics.db')
c1 = conn1.cursor()
c1.execute('''CREATE TABLE hosts (host_id INTEGER PRIMARY KEY, host_name TEXT, region TEXT)''')
c1.execute('''CREATE TABLE backups (backup_id INTEGER PRIMARY KEY, host_id INTEGER, state TEXT, size_mb INTEGER)''')

hosts_data = [
    (101, 'db-node-01', 'EU-Central'),
    (102, 'db-node-02', 'EU-Central'),
    (103, 'db-node-03', 'US-East'),
    (104, 'db-node-04', 'EU-Central')
]
c1.executemany('INSERT INTO hosts VALUES (?,?,?)', hosts_data)

backups_data = [
    (1, 101, 'SUCCESS', 1000),
    (2, 101, 'CORRUPT', 500),
    (3, 101, 'SUCCESS', 3500),
    (4, 102, 'CORRUPT', 200),
    (5, 103, 'CORRUPT', 1000),
    (6, 104, 'SUCCESS', 8000),
    (7, 104, 'CORRUPT', 100)
]
c1.executemany('INSERT INTO backups VALUES (?,?,?,?)', backups_data)
conn1.commit()
conn1.close()

# Topology DB
conn2 = sqlite3.connect('/home/user/db_backups/topology.db')
c2 = conn2.cursor()
c2.execute('''CREATE TABLE replication_edges (src_id INTEGER, dst_id INTEGER)''')
edges_data = [
    (101, 102),
    (101, 103),
    (102, 104),
    (103, 104),
    (104, 101),
    (104, 102),
    (104, 103)
]
c2.executemany('INSERT INTO replication_edges VALUES (?,?)', edges_data)
conn2.commit()
conn2.close()
"

    chown -R user:user /home/user
    chmod -R 777 /home/user
