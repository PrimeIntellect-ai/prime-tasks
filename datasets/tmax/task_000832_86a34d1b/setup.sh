#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/simulator.c
#include <stdio.h>

int main() {
    printf("seqA,42.1,44.5,43.2,41.8,45.0\n");
    printf("seqB,25.4,26.1,24.8,25.9,27.0\n");
    printf("seqC,50.1,48.5,49.2,51.0,49.8\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/proteins.fasta
>seqA
MKVLL
>seqB
MKYNN
>seqC
MKAQR
EOF

    chmod -R 777 /home/user
