#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src /home/user/bin /home/user/data

    cat << 'EOF' > /home/user/src/seq_density.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int w = atoi(argv[1]);
    if (w <= 0) return 1;

    char *buf = NULL;
    size_t size = 0;
    ssize_t len = getline(&buf, &size, stdin);
    if (len <= 0) {
        free(buf);
        return 0;
    }
    if (buf[len-1] == '\n') buf[--len] = 0;

    for (int i = 0; i <= len - w; i++) {
        int gc = 0;
        for (int j = 0; j < w; j++) {
            if (buf[i+j] == 'G' || buf[i+j] == 'C') gc++;
        }
        double p = (double)gc / w;
        double ent = 0;
        if (p > 0) ent -= p * log2(p);
        if (1-p > 0) ent -= (1-p) * log2(1-p);
        printf("%f\n", ent);
    }
    free(buf);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data/input.fasta
>Seq1
ATGCATGCATGCATGCATGCATGCATGCATGCATGCATGC
GCGCGCGCGCGCGCGCGCGCATATATATATATATATATAT
CCCGGGCCCGGGCCCGGGAAATTTCCCGGGAAATTTCCCG
>Seq2
GGCGCGGCGCGGCGCGGCGCGGCGCGGCGCGGCGCGGCGC
GGCGCGGCGCGGCGCGGCGCGGCGCGGCGCGGCGCGGCGC
>Seq3
ATATATATATATATATATATATATATATATATATATATAT
ATATATATATATATATATATATATATATATATATATATAT
EOF

    cat << 'EOF' > /home/user/data/reference.tsv
Seq1	0.820
Seq2	0.950
Seq3	0.000
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
