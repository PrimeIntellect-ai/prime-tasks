#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ binutils
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/transactions.csv
tx_id,source_node,target_node,timestamp,amount
1,101,201,1000,50
2,101,202,1010,20
3,101,203,1020,30
4,101,204,1030,100
5,102,201,1005,500
6,102,205,1015,100
EOF

    mkdir -p /app
    cat << 'EOF' > /app/prop_scorer.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    if(argc != 3) return 1;
    int node = atoi(argv[1]);
    int metric = atoi(argv[2]);
    int score = (node * 17 + metric * 31) % 1000;
    printf("[SUCCESS] Evaluation complete. Risk Metric: %d\n", score);
    return 0;
}
EOF

    gcc -O2 /app/prop_scorer.c -o /app/prop_scorer
    strip /app/prop_scorer
    chmod +x /app/prop_scorer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
