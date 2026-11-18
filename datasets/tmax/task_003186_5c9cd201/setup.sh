#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install --default-timeout=100 pytest pandas numpy

    mkdir -p /app/fastagg-1.0/src
    mkdir -p /app/data

    cat << 'EOF' > /app/fastagg-1.0/src/agg.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input_file> <output_file>\n", argv[0]);
        return 1;
    }
    FILE *in = fopen(argv[1], "r");
    FILE *out = fopen(argv[2], "w");
    if (!in || !out) return 1;

    char line[1024];
    fprintf(out, "mean,std_dev\n");
    while (fgets(line, sizeof(line), in)) {
        if (strstr(line, "val1")) continue; // skip header
        float vals[5];
        if (sscanf(line, "%f,%f,%f,%f,%f", &vals[0], &vals[1], &vals[2], &vals[3], &vals[4]) == 5) {
            float sum = 0;
            for (int i=0; i<5; i++) sum += vals[i];
            float mean = sum / 5.0;
            float sq_sum = 0;
            for (int i=0; i<5; i++) sq_sum += (vals[i] - mean) * (vals[i] - mean);
            // BUG: dividing by n instead of n - 1
            float std_dev = sqrt(sq_sum / 5.0);
            fprintf(out, "%f,%f\n", mean, std_dev);
        }
    }
    fclose(in);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /app/fastagg-1.0/Makefile
CC=gcc
CFLAGS=-O3

fastagg: src/agg.c
	$(CC) $(CFLAGS) -o fastagg src/agg.c

clean:
	rm -f fastagg
EOF

    cat << 'EOF' > /tmp/generate_data.py
import csv
import math

with open('/app/data/raw_features.csv', 'w') as f_raw, \
     open('/app/data/reference_features.csv', 'w') as f_ref:

    f_raw.write("val1,val2,val3,val4,val5\n")
    f_ref.write("mean,std_dev\n")

    for i in range(100):
        vals = [float(i), float(i+1), float(i+2), float(i+3), float(i+4)]
        f_raw.write(",".join(map(str, vals)) + "\n")
        mean = sum(vals) / 5.0
        sq_sum = sum((v - mean)**2 for v in vals)
        std_dev = math.sqrt(sq_sum / 4.0) # Correct sample std dev
        f_ref.write(f"{mean},{std_dev}\n")
EOF
    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
