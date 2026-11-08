#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install --no-cache-dir pytest numpy scipy

    mkdir -p /home/user/src
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/src/extractor.c
#include <stdio.h>
#include <ctype.h>

int main() {
    int c;
    int length = 0;
    int in_header = 0;

    while ((c = getchar()) != EOF) {
        if (c == '>') {
            if (length > 0) {
                printf("%d\n", length);
                length = 0;
            }
            in_header = 1;
        } else if (c == '\n') {
            if (in_header) {
                in_header = 0;
            }
        } else {
            if (!in_header && !isspace(c)) {
                length++;
            }
        }
    }
    if (length > 0) {
        printf("%d\n", length);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np

def write_fasta(filename, lengths):
    with open(filename, 'w') as f:
        for i, length in enumerate(lengths):
            f.write(f">seq_{i}\n")
            seq = 'A' * int(length)
            for j in range(0, len(seq), 80):
                f.write(seq[j:j+80] + "\n")

np.random.seed(42)
lengths_A = np.random.lognormal(mean=6.5, sigma=0.4, size=1000).astype(int)
lengths_A = np.clip(lengths_A, 50, 1900)
write_fasta('/home/user/data/run_A.fasta', lengths_A)

np.random.seed(123)
lengths_B = np.random.lognormal(mean=6.7, sigma=0.35, size=1200).astype(int)
lengths_B = np.clip(lengths_B, 50, 1900)
write_fasta('/home/user/data/run_B.fasta', lengths_B)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
