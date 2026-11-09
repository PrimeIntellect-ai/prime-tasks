#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy scikit-learn

    mkdir -p /app
    cat << 'EOF' > /app/seq_embedder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int base_to_idx(char c) {
    if (c == 'A' || c == 'a') return 0;
    if (c == 'C' || c == 'c') return 1;
    if (c == 'G' || c == 'g') return 2;
    if (c == 'T' || c == 't') return 3;
    return -1;
}

void process_seq(const char* seq, FILE* out) {
    float counts[64] = {0};
    int len = strlen(seq);
    int total = 0;
    for (int i = 0; i <= len - 3; i++) {
        int b1 = base_to_idx(seq[i]);
        int b2 = base_to_idx(seq[i+1]);
        int b3 = base_to_idx(seq[i+2]);
        if (b1 >= 0 && b2 >= 0 && b3 >= 0) {
            counts[b1*16 + b2*4 + b3]++;
            total++;
        }
    }
    if (total > 0) {
        for (int i = 0; i < 64; i++) counts[i] /= total;
    }
    fwrite(counts, sizeof(float), 64, out);
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* in = fopen(argv[1], "r");
    if (!in) return 1;
    FILE* out = stdout;
    if (argc >= 3) out = fopen(argv[2], "wb");

    char line[1024];
    char seq[10000] = "";
    while (fgets(line, sizeof(line), in)) {
        if (line[0] == '>') {
            if (strlen(seq) > 0) {
                process_seq(seq, out);
                seq[0] = '\0';
            }
        } else {
            line[strcspn(line, "\r\n")] = 0;
            strcat(seq, line);
        }
    }
    if (strlen(seq) > 0) process_seq(seq, out);

    fclose(in);
    if (out != stdout) fclose(out);
    return 0;
}
EOF
    gcc -O3 /app/seq_embedder.c -o /app/seq_embedder
    strip /app/seq_embedder
    rm /app/seq_embedder.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/gen_data.py
import random

def generate_fasta(filename, n_seqs):
    with open(filename, 'w') as f:
        for i in range(n_seqs):
            if random.random() < 0.5:
                bases = ['A', 'C', 'G', 'T']
                weights = [0.1, 0.4, 0.4, 0.1]
            else:
                bases = ['A', 'C', 'G', 'T']
                weights = [0.4, 0.1, 0.1, 0.4]

            seq = "".join(random.choices(bases, weights=weights, k=100))
            f.write(f">seq{i}\n{seq}\n")

generate_fasta('/home/user/data/train.fasta', 200)
generate_fasta('/home/user/data/hidden_test.fasta', 100)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
