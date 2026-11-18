#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,value,label
1,10.0,0
2,12.0,0
3,11.0,1
4,15.0,1
5,14.0,0
6,18.0,1
7,20.0,0
8,22.0,1
9,30.0,0
10,35.0,1
EOF

    cat << 'EOF' > /home/user/normalize.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define MAX_ROWS 1000

typedef struct {
    int id;
    double value;
    int label;
} Record;

int main() {
    FILE *fp = fopen("/home/user/data.csv", "r");
    if (!fp) {
        printf("Error opening data.csv\n");
        return 1;
    }

    Record data[MAX_ROWS];
    int count = 0;
    char buffer[256];

    // Skip header
    if (fgets(buffer, sizeof(buffer), fp) == NULL) return 1;

    while (fscanf(fp, "%d,%lf,%d", &data[count].id, &data[count].value, &data[count].label) == 3) {
        count++;
    }
    fclose(fp);

    int train_size = (int)(count * 0.8);

    // BUG: Computes mean over ALL data (count), causing leakage!
    double sum = 0;
    for (int i = 0; i < count; i++) { 
        sum += data[i].value;
    }
    double mean = sum / count; 

    // BUG: Computes variance over ALL data
    double sq_diff_sum = 0;
    for (int i = 0; i < count; i++) { 
        sq_diff_sum += (data[i].value - mean) * (data[i].value - mean);
    }
    double std = sqrt(sq_diff_sum / count); 

    // Write train
    FILE *ftrain = fopen("/home/user/train_norm.csv", "w");
    fprintf(ftrain, "id,value,label\n");
    for (int i = 0; i < train_size; i++) {
        fprintf(ftrain, "%d,%.4f,%d\n", data[i].id, (data[i].value - mean) / std, data[i].label);
    }
    fclose(ftrain);

    // Write test
    FILE *ftest = fopen("/home/user/test_norm.csv", "w");
    fprintf(ftest, "id,value,label\n");
    for (int i = train_size; i < count; i++) {
        fprintf(ftest, "%d,%.4f,%d\n", data[i].id, (data[i].value - mean) / std, data[i].label);
    }
    fclose(ftest);

    return 0;
}
EOF

    chmod -R 777 /home/user
