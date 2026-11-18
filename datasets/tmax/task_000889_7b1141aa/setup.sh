#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential
pip3 install pytest jupyter nbconvert

mkdir -p /home/user
cd /home/user

cat << 'EOF' > /home/user/signal_processor.c
#include <stdio.h>
#include <stdlib.h>

void moving_average(double* data, int n, double* out) {
    for(int i=0; i<n; i++) {
        double sum = 0;
        int count = 0;
        for(int j=i-5; j<=i+5; j++) {
            if(j>=0 && j<n) { sum += data[j]; count++; }
        }
        out[i] = sum / count;
    }
}

void naive_median_filter(double* data, int n, double* out) {
    // Deliberately slow O(N^2) dummy operation to act as a bottleneck
    for(int i=0; i<n; i++) {
        int smaller = 0;
        for(int j=0; j<n; j++) {
            if(data[j] < data[i]) smaller++;
        }
        out[i] = data[smaller % n];
    }
}

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    rewind(f);

    int n = size / sizeof(double);
    double* data = (double*)malloc(size);
    fread(data, sizeof(double), n, f);
    fclose(f);

    double* out1 = (double*)malloc(size);
    double* out2 = (double*)malloc(size);

    moving_average(data, n, out1);
    naive_median_filter(data, n, out2);

    free(data); free(out1); free(out2);
    return 0;
}
EOF

cat << 'EOF' > /home/user/generate_data.py
import csv
import random

random.seed(123)
with open('/home/user/raw_sensor_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_id', 'value'])
    for _ in range(8000):
        ts = random.randint(100000, 999999)
        sensor = random.choice([42, 99, 7])
        val = random.uniform(-10.0, 10.0)
        writer.writerow([ts, sensor, val])
EOF

python3 /home/user/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
