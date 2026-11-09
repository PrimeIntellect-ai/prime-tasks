#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.txt
BEGIN_RECORD
timestamp: 0.0
sensor: ALPHA
reading: 0.0
END_RECORD
BEGIN_RECORD
timestamp: 0.0
sensor: BETA
reading: 9.9
END_RECORD
BEGIN_RECORD
timestamp: 1.0
sensor: ALPHA
reading: 2.0
END_RECORD
BEGIN_RECORD
timestamp: 2.5
sensor: ALPHA
reading: 5.0
END_RECORD
BEGIN_RECORD
timestamp: 3.5
sensor: ALPHA
reading: 3.0
END_RECORD
BEGIN_RECORD
timestamp: 4.0
sensor: BETA
reading: 8.8
END_RECORD
EOF

    cat << 'EOF' > /home/user/reference.txt
0.0
0.5
2.0
4.0
EOF

    cat << 'EOF' > /home/user/ks_stat.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int compare(const void *a, const void *b) {
    double fa = *(const double*)a;
    double fb = *(const double*)b;
    return (fa > fb) - (fa < fb);
}

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *f1 = fopen(argv[1], "r");
    FILE *f2 = fopen(argv[2], "r");
    if (!f1 || !f2) return 1;

    double *v1 = malloc(1000 * sizeof(double));
    double *v2 = malloc(1000 * sizeof(double));
    int n1 = 0, n2 = 0;

    while (fscanf(f1, "%lf", &v1[n1]) == 1) n1++;
    while (fscanf(f2, "%lf", &v2[n2]) == 1) n2++;

    qsort(v1, n1, sizeof(double), compare);
    qsort(v2, n2, sizeof(double), compare);

    double max_dist = 0.0;
    int i = 0, j = 0;
    while (i < n1 && j < n2) {
        double val = (v1[i] < v2[j]) ? v1[i] : v2[j];
        while (i < n1 && v1[i] <= val) i++;
        while (j < n2 && v2[j] <= val) j++;

        double cdf1 = (double)i / n1;
        double cdf2 = (double)j / n2;
        double dist = fabs(cdf1 - cdf2);
        if (dist > max_dist) max_dist = dist;
    }

    printf("%.4f\n", max_dist);
    return 0;
}
EOF

    chmod -R 777 /home/user
