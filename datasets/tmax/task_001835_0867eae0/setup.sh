#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb libc6-dev
    pip3 install pytest

    mkdir -p /home/user/calc_metrics
    cd /home/user/calc_metrics

    cat << 'EOF' > calc_metrics.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Calculates harmonic mean.
double calc_harmonic(double *vals, int count) {
    if (count == 0) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < count; i++) {
        sum += 1.0 / vals[i];
    }
    // BUG: If sum == 0.0, this returns Inf
    return count / sum;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <input> <output>\n", argv[0]);
        return 1;
    }

    FILE *fin = fopen(argv[1], "r");
    FILE *fout = fopen(argv[2], "w");
    if (!fin || !fout) return 1;

    char line[1024];
    long histogram[10] = {0}; // Track results in buckets 0-9

    while (fgets(line, sizeof(line), fin)) {
        line[strcspn(line, "\r\n")] = 0; 
        if (strlen(line) == 0) continue;

        char *id_str = strtok(line, ";");
        char *count_str = strtok(NULL, ";");
        char *vals_str = strtok(NULL, ";");

        if (!id_str || !count_str) continue;

        int id = atoi(id_str);
        int count = atoi(count_str);

        double *vals = malloc(count * sizeof(double));

        // BUG: vals_str can be NULL if count is 0 and there is no third field
        char *v_tok = strtok(vals_str, ",");
        int i = 0;
        while (v_tok && i < count) {
            vals[i++] = atof(v_tok);
            v_tok = strtok(NULL, ",");
        }

        double h_mean = calc_harmonic(vals, count);

        fprintf(fout, "%d,%.4f\n", id, h_mean);

        // Update histogram
        // BUG: If h_mean is Inf, (int)h_mean is negative/INT_MIN, causing out-of-bounds array access and segfault
        int bucket = (int)h_mean % 10;
        if (bucket >= 0 && bucket < 10) {
            histogram[bucket]++;
        } else {
            // Unsafe fallback that triggers the segfault
            histogram[bucket]++; 
        }

        free(vals);
    }

    fprintf(fout, "---HISTOGRAM---\n");
    for(int b=0; b<10; b++) fprintf(fout, "%d:%ld\n", b, histogram[b]);

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    cat << 'EOF' > nightly.csv
1;3;2.0,2.0,2.0
2;0
3;2;1.0,-1.0
4;4;4.0,4.0,4.0,4.0
5;2;0.5,0.5
6;3;-2.0,2.0,-2.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
