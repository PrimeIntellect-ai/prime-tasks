#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/storage_metadata
    cd /home/user

    cat << 'EOF' > setup_data.py
import struct

def write_data(filename, values):
    with open(filename, 'wb') as f:
        for v in values:
            f.write(struct.pack('d', v))

data_alpha = [8.0, 12.0, 9.0, 11.0, 10.0, 10.0, 7.0, 13.0, 10.5, 9.5] 
data_beta = [24.0, 26.0, 25.0, 25.0, 25.0, 22.0, 28.0, 25.0]
data_gamma = [4.0, 6.0, 5.0, 5.0, 4.5, 5.5, 5.0, 5.0, 5.0, 5.0]

write_data('storage_metadata/node_alpha.dat', data_alpha)
write_data('storage_metadata/node_beta.dat', data_beta)
write_data('storage_metadata/node_gamma.dat', data_gamma)
EOF

    python3 setup_data.py
    rm setup_data.py

    cat << 'EOF' > analyze_latency.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

void process_file(const char* filepath, const char* nodename, FILE* out) {
    FILE *f = fopen(filepath, "rb");
    if (!f) return;

    double val;
    double sum = 0;
    double sum_sq = 0;
    int count = 0;

    while (fread(&val, sizeof(double), 1, f) == 1) {
        sum += val;
        sum_sq += val * val;
        count++;
    }
    fclose(f);

    if (count == 0) return;

    double mean = sum / count;

    // BUG: integer truncation forces variance to zero or incorrect value
    int variance = (sum_sq / count) - (mean * mean); 

    // BUG: margin becomes 0
    double margin = 1.96 * sqrt(variance / count); 

    fprintf(out, "%s,%.3f,%.3f,%.3f\n", nodename, mean, mean - margin, mean + margin);
}

int main() {
    FILE* out = fopen("/home/user/experiment_tracking.csv", "w");
    if (!out) return 1;

    fprintf(out, "Node,Mean,CI_Lower,CI_Upper\n");

    // Process files
    process_file("/home/user/storage_metadata/node_alpha.dat", "node_alpha", out);
    process_file("/home/user/storage_metadata/node_beta.dat", "node_beta", out);
    process_file("/home/user/storage_metadata/node_gamma.dat", "node_gamma", out);

    fclose(out);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
