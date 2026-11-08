#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq socat netcat gcc binutils libc-dev
    pip3 install pytest

    mkdir -p /home/user/incoming

    cat << 'EOF' > /home/user/incoming/clients.json
[
  {"client_id": "C001", "status": "active"},
  {"client_id": "C002", "status": "suspended"},
  {"client_id": "C003", "status": "active"}
]
EOF

    cat << 'EOF' > /home/user/incoming/transactions.csv
tx_id,client_id,amount
TX1001,C001,150.50
TX1002,C001,200.00
TX1003,C002,99.99
TX1004,C003,500.00
TX1005,C003,10.00
EOF

    mkdir -p /app
    cat << 'EOF' > /tmp/tx_signer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned long hash(unsigned char *str) {
    unsigned long hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c; 
    return hash;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%s_%s_SECRET99", argv[1], argv[2]);
    printf("%lx\n", hash((unsigned char *)buffer));
    return 0;
}
EOF

    gcc -O2 /tmp/tx_signer.c -o /app/tx_signer
    strip /app/tx_signer
    chmod +x /app/tx_signer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
