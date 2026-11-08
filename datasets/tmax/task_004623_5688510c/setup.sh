#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
ID,Feature_A,Feature_B,Feature_C,Target
1,1.0,2.0,3.0,10.0
2,4.0,5.0,6.0,20.0
3,5.0,3.0,1.5,15.0
4,5.1,3.2,1.2,15.5
5,9.0,8.0,7.0,30.0
6,5.2,2.9,1.0,14.8
7,0.0,0.0,0.0,5.0
8,10.0,1.0,1.0,22.0
9,4.9,3.1,1.1,15.2
10,2.0,2.0,2.0,12.0
EOF

    cat << 'EOF' > /home/user/analyze.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_ROWS 100

typedef struct {
    int id;
    double a;
    double b;
    double c;
    double target;
    double distance;
} Record;

int main() {
    FILE *file = fopen("/home/user/dataset.csv", "r");
    if (!file) {
        printf("Error opening file.\n");
        return 1;
    }

    char line[256];
    fgets(line, sizeof(line), file); // Skip header

    Record data[MAX_ROWS];
    int count = 0;

    // Read data
    while (fgets(line, sizeof(line), file) && count < MAX_ROWS) {
        sscanf(line, "%d,%lf,%lf,%lf,%lf", 
               &data[count].id, &data[count].a, &data[count].b, &data[count].c, &data[count].target);
        count++;
    }
    fclose(file);

    // Calculate Pearson Correlation for Feature_A vs Target
    // BUG 1: Using int for accumulators causes truncation/zeroing
    int sum_a = 0, sum_b = 0, sum_c = 0, sum_t = 0;
    int sum_aa = 0, sum_bb = 0, sum_cc = 0, sum_tt = 0;
    int sum_at = 0, sum_bt = 0, sum_ct = 0;

    for (int i = 0; i < count; i++) {
        sum_a += data[i].a; sum_b += data[i].b; sum_c += data[i].c; sum_t += data[i].target;
        sum_aa += data[i].a * data[i].a;
        sum_bb += data[i].b * data[i].b;
        sum_cc += data[i].c * data[i].c;
        sum_tt += data[i].target * data[i].target;
        sum_at += data[i].a * data[i].target;
        sum_bt += data[i].b * data[i].target;
        sum_ct += data[i].c * data[i].target;
    }

    double n = count;
    double cor_a = (n * sum_at - sum_a * sum_t) / sqrt((n * sum_aa - sum_a * sum_a) * (n * sum_tt - sum_t * sum_t));
    double cor_b = (n * sum_bt - sum_b * sum_t) / sqrt((n * sum_bb - sum_b * sum_b) * (n * sum_tt - sum_t * sum_t));
    double cor_c = (n * sum_ct - sum_c * sum_t) / sqrt((n * sum_cc - sum_c * sum_c) * (n * sum_tt - sum_t * sum_t));

    // Calculate Distance to Query [5.0, 3.0, 1.0]
    double qA = 5.0, qB = 3.0, qC = 1.0;
    for (int i = 0; i < count; i++) {
        // BUG 2: Incorrect distance formula (not squared, no sqrt)
        data[i].distance = (data[i].a - qA) + (data[i].b - qB) + (data[i].c - qC);
    }

    // Sort by distance (Bubble sort)
    for (int i = 0; i < count - 1; i++) {
        for (int j = 0; j < count - i - 1; j++) {
            if (data[j].distance > data[j+1].distance) {
                Record temp = data[j];
                data[j] = data[j+1];
                data[j+1] = temp;
            }
        }
    }

    printf("Correlations: Feature_A:%.4f, Feature_B:%.4f, Feature_C:%.4f\n", cor_a, cor_b, cor_c);
    printf("Top 3 Similar IDs: %d, %d, %d\n", data[0].id, data[1].id, data[2].id);

    return 0;
}
EOF

    chmod -R 777 /home/user
