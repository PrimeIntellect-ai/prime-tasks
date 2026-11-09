#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('financial_audit.db')
c = conn.cursor()

c.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE transfers (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp INTEGER)')

accounts = [
    (1, 'ShellCorp'),
    (2, 'MixerA'),
    (3, 'MixerB'),
    (4, 'LegitCorp'),
    (5, 'OffshoreVault'),
    (6, 'BribeAccount')
]
c.executemany('INSERT INTO accounts VALUES (?,?)', accounts)

transfers = [
    # ShellCorp (1) transfers
    (1, 1, 2, 100, 1), # avg 100, not > avg
    (2, 1, 3, 100, 2), # avg 100, not > avg
    (3, 1, 2, 500, 3), # avg 233.3, FLAG (1 -> 2)
    (4, 1, 6, 50, 4),  # avg 216.6, not > avg

    # MixerA (2) transfers
    (5, 2, 4, 1000, 1), # avg 1000, not > avg
    (6, 2, 5, 2000, 2), # avg 1500, FLAG (2 -> 5)
    (7, 2, 6, 2500, 3), # avg 1833.3, FLAG (2 -> 6)
    (8, 2, 3, 3000, 4), # avg 2500, FLAG (2 -> 3)

    # MixerB (3) transfers
    (9, 3, 4, 100, 1),  # avg 100, not > avg
    (10, 3, 5, 500, 2), # avg 300, FLAG (3 -> 5)

    # LegitCorp (4) transfers
    (11, 4, 5, 10000, 1) # avg 10000, not > avg
]
c.executemany('INSERT INTO transfers VALUES (?,?,?,?,?)', transfers)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
