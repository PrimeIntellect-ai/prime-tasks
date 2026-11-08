#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq gawk gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/fetch_sales_graph.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    srand(42);
    printf("E0||%.2f\n", (float)(rand() % 10000) / 100.0);
    for (int i = 1; i < 50000; i++) {
        int mgr = rand() % i;
        float sales = (float)(rand() % 10000) / 100.0;
        printf("E%d|E%d|%.2f\n", i, mgr, sales);
    }
    return 0;
}
EOF

    gcc -O2 /app/fetch_sales_graph.c -o /app/fetch_sales_graph
    strip /app/fetch_sales_graph
    rm /app/fetch_sales_graph.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
