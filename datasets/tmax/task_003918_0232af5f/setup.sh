#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data /home/user/sim

    cat << 'EOF' > /home/user/data/alignment.fasta
>seq1
AGAGAGAGAGAGAGAG
AGAGAGAGAGAGAGAG
>seq2
ATAGATAGATAGATAG
ATAGATAGATAGATAG
EOF

    cat << 'EOF' > /home/user/sim/sub_matrix.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: %s <seq1> <seq2>\n", argv[0]);
        return 1;
    }
    char *seq1 = argv[1];
    char *seq2 = argv[2];
    double matrix[4][4] = {0};

    int map[256] = {0};
    map['A'] = 0; map['C'] = 1; map['G'] = 2; map['T'] = 3;

    for (int i = 0; seq1[i] && seq2[i]; i++) {
        matrix[map[(unsigned char)seq1[i]]][map[(unsigned char)seq2[i]]]++;
    }

    for (int i = 0; i < 4; i++) {
        double sum = 0;
        for (int j = 0; j < 4; j++) sum += matrix[i][j];
        for (int j = 0; j < 4; j++) {
            matrix[i][j] /= sum;
            printf("%.4f ", matrix[i][j]);
        }
        printf("\n");
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
