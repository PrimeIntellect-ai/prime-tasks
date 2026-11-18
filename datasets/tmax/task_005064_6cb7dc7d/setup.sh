#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /app

    # Generate data and ground truth
    cat << 'EOF' > /app/setup_data.py
import pandas as pd
import os

# T1.csv
t1 = pd.DataFrame({'u_id': [1, 2, 3]})
t1.to_csv('/home/user/data/T1.csv', index=False)

# T2.csv
t2 = pd.DataFrame({
    't_id': [1, 2, 3, 4],
    'u_id': [1, 1, 2, 3],
    'amount': [100.0, 50.0, 200.0, 150.0],
    'currency': ['USD', 'EUR', 'USD', 'GBP']
})
t2.to_csv('/home/user/data/T2.csv', index=False)

# T3.csv
t3 = pd.DataFrame({
    'currency': ['USD', 'USD', 'EUR', 'EUR', 'GBP', 'GBP'],
    'rate': [1.0, 1.0, 1.1, 1.2, 1.3, 1.4],
    'timestamp': ['2023-01-01', '2023-01-02', '2023-01-01', '2023-01-02', '2023-01-01', '2023-01-02']
})
t3.to_csv('/home/user/data/T3.csv', index=False)

# Ground truth (using latest rate per currency)
# USD: 1.0, EUR: 1.2, GBP: 1.4
# u_id 1: 100*1.0 + 50*1.2 = 160.0
# u_id 2: 200*1.0 = 200.0
# u_id 3: 150*1.4 = 210.0
gt = pd.DataFrame({
    'entity_id': [1, 2, 3],
    'total_value': [160.0, 200.0, 210.0]
})
gt.to_csv('/app/ground_truth.csv', index=False)
EOF

    python3 /app/setup_data.py

    # Create dummy legacy calc C source
    cat << 'EOF' > /app/legacy_calc.c
#include <stdio.h>

int main() {
    FILE *f1 = fopen("/home/user/data/T1.csv", "r");
    FILE *f2 = fopen("/home/user/data/T2.csv", "r");
    FILE *f3 = fopen("/home/user/data/T3.csv", "r");
    if(f1) fclose(f1);
    if(f2) fclose(f2);
    if(f3) fclose(f3);

    printf("entity_id,total_value\n");
    printf("1,315.00\n");
    printf("2,400.00\n");
    printf("3,405.00\n");
    return 0;
}
EOF

    gcc -O2 /app/legacy_calc.c -o /app/legacy_calc
    strip /app/legacy_calc
    rm /app/legacy_calc.c /app/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
