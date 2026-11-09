#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/src
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/src/seq_compare.c
#include <stdio.h>

int sequence_distance(const char* s1, const char* s2, int len) {
    int dist = 0;
    for(int i = 0; i < len; i++) {
        if(s1[i] != s2[i]) {
            dist++;
        }
    }
    return dist;
}
EOF

    cat << 'EOF' > /home/user/data/sequences.txt
ATGCGT
ATCCGT
TTGCGT
ATGCGA
CCGTTA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
