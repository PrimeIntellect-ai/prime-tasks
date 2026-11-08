#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src /home/user/data /home/user/bin /home/user/output /home/user/scripts

    cat << 'EOF' > /home/user/src/seq_cov.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_SEQS 100
#define MAX_LEN 1000

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char seqs[MAX_SEQS][MAX_LEN];
    int n = 0;
    while (fscanf(f, "%s", seqs[n]) == 1 && n < MAX_SEQS) {
        n++;
    }
    fclose(f);

    double mat[MAX_SEQS][MAX_SEQS];
    for (int i=0; i<n; i++) {
        for (int j=0; j<n; j++) {
            double score = 0;
            int len_i = strlen(seqs[i]);
            int len_j = strlen(seqs[j]);
            int min_len = len_i < len_j ? len_i : len_j;
            for(int k=0; k<min_len; k++) {
                if (seqs[i][k] == seqs[j][k]) score += 1.0;
            }
            // Ensure positive definiteness
            if (i == j) score += 10.0; 
            mat[i][j] = score;
        }
    }

    for (int i=0; i<n; i++) {
        for (int j=0; j<n; j++) {
            printf("%.4f%s", mat[i][j], j==n-1 ? "" : " ");
        }
        printf("\n");
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data/seqs.txt
ACGT
ACCA
TGCA
TGGT
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
