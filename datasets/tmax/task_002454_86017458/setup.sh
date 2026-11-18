#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak
    pip3 install pytest

    mkdir -p /app

    # Generate lab notes audio
    espeak -w /app/lab_notes.wav "To calculate the stability score, iterate over the sequence using a 1-based index. Multiply the 1-based index by the nucleotide weight: A is 13, C is 27, G is 31, and T is 42. Sum these values across the entire sequence. After adding the value for each position, take the modulo 10009 of the running sum to prevent overflow. The final result is the stability score."

    # Create and compile oracle scorer
    cat << 'EOF' > /app/oracle_scorer.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    char *seq = argv[1];
    long long score = 0;
    int len = strlen(seq);
    for (int i = 0; i < len; i++) {
        int weight = 0;
        if (seq[i] == 'A') weight = 13;
        else if (seq[i] == 'C') weight = 27;
        else if (seq[i] == 'G') weight = 31;
        else if (seq[i] == 'T') weight = 42;

        score += (i + 1) * weight;
        score %= 10009;
    }
    printf("%lld\n", score);
    return 0;
}
EOF

    gcc -O3 /app/oracle_scorer.c -o /app/oracle_scorer
    rm /app/oracle_scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
