#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gawk bc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 4 || strcmp(argv[1], "--prior") != 0) {
        fprintf(stderr, "Usage: %s --prior <float> <csv_file>\n", argv[0]);
        return 1;
    }
    double prior = atof(argv[2]);
    FILE *f = fopen(argv[3], "r");
    if (!f) return 1;

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        char id[128];
        double a, b, c;
        if (sscanf(line, "%127[^,],%lf,%lf,%lf", id, &a, &b, &c) == 4) {
            double s = 0.40 * a + 0.35 * b + 0.25 * c;
            double num = s * prior;
            double den = num + (1.0 - s) * (1.0 - prior);
            double posterior = num / den;
            printf("%s,%.6f\n", id, posterior);
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/legacy_scorer
    strip /app/legacy_scorer
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
