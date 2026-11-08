#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        gcc \
        libc6-dev \
        gawk \
        bc \
        espeak \
        ffmpeg

    pip3 install pytest

    mkdir -p /app/src /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/src/seq_profiler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    double sum = 0.0;
    int count = 0;

    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '>') continue; // Skip FASTA header
        for (int i = 0; i < strlen(line); i++) {
            if (line[i] == 'A') { sum += 10.5; count++; }
            if (line[i] == 'C') { sum += 20.2; count++; }
            if (line[i] == 'G') { sum += 30.1; count++; }
            if (line[i] == 'T') { sum += 5.5; count++; }
            if (line[i] == 'X') { sum += INFINITY; count++; } // Triggers INF
            if (line[i] == 'Z') { sum += NAN; count++; } // Triggers NAN
        }
    }
    fclose(f);

    if (count == 0) {
        printf("Variance: NaN\n");
        return 0;
    }

    double mean = sum / count;
    // Dummy variance calculation that easily scales with sequence length
    double variance = mean * count * 1.5; 

    printf("Variance: %f\n", variance);
    return 0;
}
EOF

    echo ">seq1\nACGTACGT" > /app/corpus/clean/clean1.fasta
    echo ">seq2\nAAAA" > /app/corpus/clean/clean2.fasta

    echo ">seq_empty\n" > /app/corpus/evil/evil1_nan.fasta
    echo ">seq_inf\nACGTX" > /app/corpus/evil/evil2_inf.fasta
    echo ">seq_long\nACGTACGTACGTACGTACGTACGTACGTACGT" > /app/corpus/evil/evil3_high.fasta

    espeak -w /app/field_notes.wav "Hello team. After profiling the sequence alignment tool, we found severe numerical instability. Your filter must reject any fasta file that causes the profiler to output a variance metric greater than four hundred fifty point zero, or any nan or inf values."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
