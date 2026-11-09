#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest flask fastapi uvicorn

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    int src = atoi(argv[1]);
    int dst = atoi(argv[2]);
    int cost = ((src * 17) + (dst * 31)) % 50;
    if (cost < 0) cost = -cost;
    cost += 1;
    printf("%d\n", cost);
    return 0;
}
EOF
    gcc -O2 -s /app/oracle.c -o /app/link_cost_oracle
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/init.sql
CREATE TABLE routers (id INTEGER PRIMARY KEY, name TEXT, tier TEXT);
CREATE TABLE links (source_id INTEGER, target_id INTEGER);

INSERT INTO routers VALUES (1, 'core-1', 'core'), (2, 'core-2', 'core'), (3, 'agg-1', 'aggregation'), (4, 'agg-2', 'aggregation'), (5, 'edge-1', 'edge'), (6, 'edge-2', 'edge');
INSERT INTO links VALUES (1, 3), (1, 4), (2, 3), (2, 4), (3, 5), (4, 5), (4, 6), (1, 2), (5, 6);
EOF
    sqlite3 /home/user/network.db < /tmp/init.sql
    rm /tmp/init.sql

    chmod -R 777 /home/user
    chmod -R 777 /app
