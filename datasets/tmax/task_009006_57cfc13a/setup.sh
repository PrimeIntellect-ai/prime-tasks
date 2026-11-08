#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/data/target.fasta
>seq1
ACGTACGTGCGCGCATATATGCGCGCACGT
EOF

    cat << 'EOF' > /home/user/src/fasta_stat.c
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    int count = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '>') count++;
    }
    printf("Number of sequences: %d\n", count);
    fclose(f);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
