#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest networkx flask requests

    # Create key_deriver binary
    mkdir -p /app
    cat << 'EOF' > /app/key_deriver.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    unsigned long hash = 5381;
    int c;
    char *str = argv[1];
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    printf("%lx\n", hash);
    return 0;
}
EOF
    gcc -O2 /app/key_deriver.c -o /app/key_deriver
    strip /app/key_deriver
    rm /app/key_deriver.c

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate SQLite database
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()
c.execute('CREATE TABLE jobs (id TEXT PRIMARY KEY, type TEXT)')
c.execute('CREATE TABLE deps (source TEXT, target TEXT)')

hubs = ['job_42', 'job_100', 'job_333', 'job_500', 'job_777']
nodes = [f'job_{i}' for i in range(1001)]

for node in nodes:
    if node in hubs:
        c.execute('INSERT INTO jobs VALUES (?, ?)', (node, 'full'))
    else:
        c.execute('INSERT INTO jobs VALUES (?, ?)', (node, 'incremental'))

for i, node in enumerate(nodes):
    if node not in hubs:
        # distribute edges among hubs
        t = hubs[i % len(hubs)]
        c.execute('INSERT INTO deps VALUES (?, ?)', (node, t))

conn.commit()
conn.close()
EOF
    python3 /tmp/gen_db.py
    rm /tmp/gen_db.py

    chmod -R 777 /home/user
