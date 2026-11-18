#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils rustc cargo
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/seq_align_scorer.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define MATCH 4
#define MISMATCH -3
#define GAP -2

int max3(int a, int b, int c) {
    int m = a > b ? a : b;
    return m > c ? m : c;
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    char *seq1 = argv[1];
    char *seq2 = argv[2];
    int len1 = strlen(seq1);
    int len2 = strlen(seq2);

    int **dp = malloc((len1 + 1) * sizeof(int *));
    for (int i = 0; i <= len1; i++) {
        dp[i] = malloc((len2 + 1) * sizeof(int));
    }

    for (int i = 0; i <= len1; i++) dp[i][0] = i * GAP;
    for (int j = 0; j <= len2; j++) dp[0][j] = j * GAP;

    for (int i = 1; i <= len1; i++) {
        for (int j = 1; j <= len2; j++) {
            int score = (seq1[i-1] == seq2[j-1]) ? MATCH : MISMATCH;
            dp[i][j] = max3(
                dp[i-1][j-1] + score,
                dp[i-1][j] + GAP,
                dp[i][j-1] + GAP
            );
        }
    }

    printf("%d\n", dp[len1][len2]);
    return 0;
}
EOF

    gcc -O2 /app/seq_align_scorer.c -o /app/seq_align_scorer
    strip /app/seq_align_scorer
    rm /app/seq_align_scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
