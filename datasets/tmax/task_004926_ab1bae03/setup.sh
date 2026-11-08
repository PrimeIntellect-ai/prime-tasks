#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/math_lib.c
float calc_variance(float* arr, int n) {
    float sum = 0.0, mean, variance = 0.0;
    for(int i = 0; i < n; ++i) sum += arr[i];
    mean = sum / n;
    for(int i = 0; i < n; ++i) variance += (arr[i] - mean) * (arr[i] - mean);
    return variance / n;
}
EOF

    sqlite3 /home/user/data.db "CREATE TABLE records (id INTEGER PRIMARY KEY, input_mean REAL);"

    chmod -R 777 /home/user
