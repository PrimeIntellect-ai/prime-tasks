#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libgomp1
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/data.fasta
>seq1
ACGTACGTACGTACGT
>seq2
AAAAACCCCCGGGGGTTTTT
>seq3
ATGCATGCATGC
>seq4
ACACACACACACACAC
>seq5
TGTGTGTGTGTGTGTG
EOF

cat << 'EOF' > /home/user/kmer_dist.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <omp.h>

#define KMER_SIZE 3
#define NUM_KMERS 64

int kmer_to_index(char *kmer) {
    int idx = 0;
    for (int i = 0; i < KMER_SIZE; i++) {
        idx <<= 2;
        switch (kmer[i]) {
            case 'A': break;
            case 'C': idx |= 1; break;
            case 'G': idx |= 2; break;
            case 'T': idx |= 3; break;
            default: return -1;
        }
    }
    return idx;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[1024];
    int counts[NUM_KMERS] = {0};
    int total_kmers = 0;

    char **sequences = malloc(10000 * sizeof(char*));
    int num_seqs = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '>') continue;
        line[strcspn(line, "\n")] = 0;
        sequences[num_seqs++] = strdup(line);
    }
    fclose(f);

    #pragma omp parallel for
    for (int i = 0; i < num_seqs; i++) {
        int len = strlen(sequences[i]);
        for (int j = 0; j <= len - KMER_SIZE; j++) {
            int idx = kmer_to_index(&sequences[i][j]);
            if (idx != -1) {
                counts[idx]++;
                total_kmers++;
            }
        }
    }

    double P[NUM_KMERS];
    for (int i = 0; i < NUM_KMERS; i++) {
        P[i] = (double)counts[i] / total_kmers;
    }

    double Q_val = 1.0 / NUM_KMERS;
    double kl = 0.0;
    for (int i = 0; i < NUM_KMERS; i++) {
        kl += P[i] * log2(P[i] / Q_val);
    }

    printf("KL Divergence: %.4f\n", kl);
    return 0;
}
EOF

chmod -R 777 /home/user
