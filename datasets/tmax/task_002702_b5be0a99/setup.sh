#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas

    mkdir -p /app/data/evil
    mkdir -p /app/data/clean

    # Create dummy C source for the price_aggregator binary
    cat << 'EOF' > /tmp/price_aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[1024];
    float total_price = 0.0;
    while (fgets(buffer, sizeof(buffer), stdin)) {
        char *token = strtok(buffer, ",");
        int col = 0;
        float price = 0.0;
        while (token) {
            if (col == 2) {
                price = atof(token);
            }
            token = strtok(NULL, ",");
            col++;
        }
        total_price += price;
    }
    return 0;
}
EOF

    gcc -O2 /tmp/price_aggregator.c -o /app/price_aggregator
    strip /app/price_aggregator
    rm /tmp/price_aggregator.c

    # Create clean corpus data
    cat << 'EOF' > /app/data/clean/data1.csv
timestamp,tx_id,price,comment
1000,tx1,10.5,clean comment
1001,tx2,11.0,another comment
1002,tx3,12.5,third comment
EOF

    # Create evil corpus data
    cat << 'EOF' > /app/data/evil/data1.csv
timestamp,tx_id,price,comment
1000,tx1,10.5,"evil
comment"
1000,tx1,10.5,"duplicate"
1002,tx2,15.0,gap before this
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
