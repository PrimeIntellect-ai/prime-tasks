#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > dataset.fasta
>seq1
GCGCGCGCGCGCATATATAT
>seq2
GCGCGCGCGCGCATATATAT
>seq3
GCGCGCGCGCGCATATATAT
>seq4
GCGCGCGCGCGCATATATAT
>seq5
GCGCGCGCGCGCATATATAT
>seq6
GCGCGCGCGCGCATATATAT
>seq7
GCGCGCGCGCGCATATATAT
>seq8
GCGCGCGCGCGCATATATAT
>seq9
GCGCGCGCGCGCATATATAT
>seq10
GCGCGCGCGCGCATATATAT
EOF

    cat << 'EOF' > seq_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_SEQS 1000
#define MAX_LEN 200

int main() {
    FILE *f = fopen("/home/user/dataset.fasta", "r");
    if (!f) {
        printf("Error opening file.\n");
        return 1;
    }
    char line[MAX_LEN];
    double gc_content[MAX_SEQS];
    int n = 0;

    char sequences[MAX_SEQS][MAX_LEN];

    while(fgets(line, sizeof(line), f)) {
        if(line[0] == '>') continue;
        strcpy(sequences[n], line);
        int len = 0;
        int gc = 0;
        for(int i=0; sequences[n][i] != '\0' && sequences[n][i] != '\n'; i++) {
            if(sequences[n][i] == 'G' || sequences[n][i] == 'C') gc++;
            len++;
        }
        if(len > 0) {
            gc_content[n] = (double)gc / len;
            n++;
        }
    }
    fclose(f);

    double mu = 0.5;
    // BUG: Step size does not adapt to the number of samples, causing divergence
    double alpha = 0.8; 

    for(int iter=0; iter<500; iter++) {
        double grad = 0.0;
        for(int i=0; i<n; i++) {
            grad += (gc_content[i] - mu);
        }
        mu = mu + alpha * grad; 
    }

    double var = 0.0;
    for(int i=0; i<n; i++) {
        var += (gc_content[i] - mu) * (gc_content[i] - mu);
    }
    var /= n;

    // Small epsilon to prevent division by zero in variance for identical sequences
    if (var < 1e-9) var = 1e-9;

    double z_score = (mu - 0.5) / sqrt(var / n);

    printf("Fitted Mean: %.4f\n", mu);
    printf("Fitted Variance: %.4f\n", var);
    printf("Z-score: %.4f\n", z_score);

    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
