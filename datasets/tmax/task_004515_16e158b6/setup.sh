#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/malware_analysis
    cd /home/user/malware_analysis

    cat << 'EOF' > requirements.txt
requests==2.26.0
urllib3==1.20
EOF

    cat << 'EOF' > parser.py
import sys
import struct

def parse_tlv(filepath):
    intervals = []
    with open(filepath, 'rb') as f:
        while True:
            header = f.read(3)
            if not header or len(header) < 3:
                break
            msg_type, length = struct.unpack('>BH', header)
            data = f.read(length)

            # BUG: Assumes data is always present. If length is 0, data is empty.
            # data[0] will raise IndexError.
            if msg_type == 1:
                intervals.append(data[0])
            elif msg_type == 2:
                intervals.append(data[0] * 2)

    for i in intervals:
        print(i)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    parse_tlv(sys.argv[1])
EOF

    cat << 'EOF' > cluster_beacons.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define MAX_ITERS 100
#define K 2

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    double data[1000];
    int n = 0;
    while (fscanf(f, "%lf", &data[n]) == 1) {
        n++;
    }
    fclose(f);

    if (n == 0) return 0;

    double centroids[K] = {10.0, 50.0};
    int assignments[1000] = {0};

    for (int iter = 0; iter < MAX_ITERS; iter++) {
        int changed = 0;

        // Assign
        for (int i = 0; i < n; i++) {
            double min_dist = 1e9;
            int best_k = 0;
            for (int k = 0; k < K; k++) {
                double dist = fabs(data[i] - centroids[k]);
                if (dist < min_dist) {
                    min_dist = dist;
                    best_k = k;
                }
            }
            if (assignments[i] != best_k) {
                assignments[i] = best_k;
                changed = 1;
            }
        }

        if (!changed) break;

        // Update
        double sums[K] = {0};
        int counts[K] = {0};
        for (int i = 0; i < n; i++) {
            sums[assignments[i]] += data[i];
            counts[assignments[i]]++;
        }

        for (int k = 0; k < K; k++) {
            // BUG: Division by zero if counts[k] == 0
            centroids[k] = sums[k] / counts[k];
        }
    }

    printf("Centroids:\n");
    for (int k = 0; k < K; k++) {
        printf("%.2f\n", centroids[k]);
    }

    return 0;
}
EOF

    cat << 'EOF' > generate_bin.py
import struct
with open('suspicious_log.bin', 'wb') as f:
    f.write(struct.pack('>BH', 1, 1) + b'\x0c') # 12
    f.write(struct.pack('>BH', 1, 1) + b'\x0e') # 14
    f.write(struct.pack('>BH', 3, 0)) # Edge case (length 0)
    f.write(struct.pack('>BH', 1, 1) + b'\x0d') # 13
    f.write(struct.pack('>BH', 2, 1) + b'\x19') # 25 * 2 = 50
    f.write(struct.pack('>BH', 2, 1) + b'\x1a') # 26 * 2 = 52
EOF
    python3 generate_bin.py
    rm generate_bin.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
