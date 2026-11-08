#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    # Create dataset.csv
    cat << 'EOF' > /home/user/data.csv
0,10.0
1,20.0
2,30.0
3,40.0
4,50.0
5,60.0
6,70.0
7,80.0
8,90.0
9,100.0
EOF

    # Create cleaner.c with the leakage bug
    cat << 'EOF' > /home/user/cleaner.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define MAX_ROWS 1000

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    int ids[MAX_ROWS];
    double vals[MAX_ROWS];
    int count = 0;

    while (fscanf(f, "%d,%lf", &ids[count], &vals[count]) == 2) {
        count++;
    }
    fclose(f);

    int train_count = (int)(count * 0.8);

    // BUG: Data leakage! Calculating mean over the ENTIRE dataset
    double sum = 0;
    for (int i = 0; i < count; i++) {
        sum += vals[i];
    }
    double mean = sum / count;

    // BUG: Data leakage! Calculating std over the ENTIRE dataset
    double sq_diff_sum = 0;
    for (int i = 0; i < count; i++) {
        sq_diff_sum += (vals[i] - mean) * (vals[i] - mean);
    }
    double std = sqrt(sq_diff_sum / count);

    FILE *f_train = fopen("train_norm.csv", "w");
    for (int i = 0; i < train_count; i++) {
        fprintf(f_train, "%d,%.4f\n", ids[i], (vals[i] - mean) / std);
    }
    fclose(f_train);

    FILE *f_test = fopen("test_norm.csv", "w");
    for (int i = train_count; i < count; i++) {
        fprintf(f_test, "%d,%.4f\n", ids[i], (vals[i] - mean) / std);
    }
    fclose(f_test);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
