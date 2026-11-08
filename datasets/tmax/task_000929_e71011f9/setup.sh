#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest networkx

    # Create directories
    mkdir -p /app/data /app/corpus/evil /app/corpus/clean

    # Run Python script to generate data and corpus
    python3 -c "
import sqlite3
import os
import json

os.makedirs('/app/data', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)
os.makedirs('/app/corpus/clean', exist_ok=True)

conn = sqlite3.connect('/app/data/corp.db')
c = conn.cursor()
c.execute('CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE ownership (parent_id INTEGER, child_id INTEGER)')

edges_1 = [(1,2), (1,3), (2,4), (3,5), (5,6), (6,7), (7,8), (8,9), (9,10)]
edges_2 = [(11,12), (12,13), (11,14), (14,15), (15,16), (16,17), (17,18), (18,19), (19,20)]

for i in range(1, 21):
    c.execute('INSERT INTO entities VALUES (?, ?)', (i, f'Corp_{i}'))

c.executemany('INSERT INTO ownership VALUES (?, ?)', edges_1 + edges_2)
conn.commit()
conn.close()

with open('/app/corpus/evil/tx1.json', 'w') as f:
    json.dump({'tx_id': 'tx_1', 'sender_id': 1, 'receiver_id': 10, 'amount': 60000.0}, f)
with open('/app/corpus/evil/tx2.json', 'w') as f:
    json.dump({'tx_id': 'tx_2', 'sender_id': 19, 'receiver_id': 11, 'amount': 150000.0}, f)

with open('/app/corpus/clean/tx3.json', 'w') as f:
    json.dump({'tx_id': 'tx_3', 'sender_id': 2, 'receiver_id': 8, 'amount': 49000.0}, f)
with open('/app/corpus/clean/tx4.json', 'w') as f:
    json.dump({'tx_id': 'tx_4', 'sender_id': 4, 'receiver_id': 15, 'amount': 80000.0}, f)
with open('/app/corpus/clean/tx5.json', 'w') as f:
    json.dump({'tx_id': 'tx_5', 'sender_id': 1, 'receiver_id': 20, 'amount': 10000.0}, f)
"

    # Create dummy legacy auditor binary
    cat << 'EOF' > /tmp/legacy_auditor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    return 0;
}
EOF
    gcc -o /app/legacy_auditor /tmp/legacy_auditor.c
    strip /app/legacy_auditor
    rm /tmp/legacy_auditor.c

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
