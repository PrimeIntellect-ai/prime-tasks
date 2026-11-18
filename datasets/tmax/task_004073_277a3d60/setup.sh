#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/report

    cd /home/user/app
    sqlite3 data.db "PRAGMA journal_mode=WAL;"
    sqlite3 data.db "CREATE TABLE metrics(node_id INT, load_avg REAL);"
    sqlite3 data.db "INSERT INTO metrics VALUES(1, 0.5), (2, 0.9), (3, 0.85), (4, 0.95), (5, 0.2), (6, 0.88), (7, 0.99);"

    cat << 'EOF' > /tmp/service.c
#include <stdlib.h>
#include <stdio.h>

void process_metrics_unfreed_alloc() {
    void* leak = malloc(2048);
    // intentional memory leak
}

int main() {
    const char* query = "SELECT node_id, load_avg FROM metrics WHERE load_avg > 0.8 ORDER BY node_id DESC LIMIT 5;";
    process_metrics_unfreed_alloc();
    printf("Executing: %s\n", query);
    return 0;
}
EOF

    gcc /tmp/service.c -o /home/user/app/service_bin
    rm /tmp/service.c

    chmod -R 777 /home/user
