#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest networkx pandas

    mkdir -p /app
    cat << 'EOF' > /app/legacy_pathfinder.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char *argv[]) {
    if(argc != 2) return 1;
    int seed = atoi(argv[1]);
    srand(seed);
    printf("source_node_id,target_node_id\n");
    for(int i=0; i<50000; i++) {
        int src = (rand() % 1000) + 1;
        int tgt = (rand() % 1000) + 1;
        if (src != tgt) {
            printf("%d,%d\n", src, tgt);
        }
    }
    return 0;
}
EOF
    gcc -O2 /app/legacy_pathfinder.c -o /app/legacy_pathfinder
    strip -s /app/legacy_pathfinder
    rm /app/legacy_pathfinder.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

random.seed(42)
regions = ['us-east', 'us-west', 'eu-central', 'ap-south']

conn = sqlite3.connect('/home/user/backup_meta.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, region TEXT, is_global INTEGER)')

for i in range(1, 1001):
    reg = regions[random.randint(0, 3)]
    is_glob = 1 if i % 25 == 0 else 0
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (i, reg, is_glob))

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
