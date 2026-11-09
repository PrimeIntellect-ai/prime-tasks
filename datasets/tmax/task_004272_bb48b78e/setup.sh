#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc
    pip3 install pytest

    mkdir -p /home/user/motif_project

    cat << 'EOF' > /home/user/motif_project/scorer.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    char *seq = argv[1];
    int score = 0;
    int len = strlen(seq);

    // Check for invalid characters
    for(int i=0; i<len; i++) {
        if(seq[i] != 'A' && seq[i] != 'C' && seq[i] != 'G' && seq[i] != 'T') {
            printf("-9999\n");
            return 0;
        }
    }

    for(int i=0; i<len-2; i++) {
        if(seq[i]=='A' && seq[i+1]=='T' && seq[i+2]=='G') score += 15;
    }
    for(int i=0; i<len-1; i++) {
        if(seq[i]=='C' && seq[i+1]=='G') score += 7;
        if(seq[i]=='G' && seq[i+1]=='C') score += 5;
        if(seq[i]=='T' && seq[i+1]=='A') score -= 5;
        if(seq[i]=='T' && seq[i+1]=='T') score -= 3;
    }
    printf("%d\n", score);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
