#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > /home/user/experiments.csv
1,10.0,10.0
2,20.0,20.0
3,30.0,30.0
4,15.0,25.0
5,25.0,15.0
6,12.0,28.0
7,28.0,12.0
8,5.0,5.0
9,40.0,40.0
10,14.0,26.0
EOF

cat << 'EOF' > /home/user/pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define TOTAL_ROWS 10
#define NUM_REF 7
#define NUM_QUERY 3

typedef struct {
    int id;
    float f1;
    float f2;
} Experiment;

int main() {
    FILE *fp = fopen("/home/user/experiments.csv", "r");
    if (!fp) {
        printf("Cannot open file.\n");
        return 1;
    }

    Experiment exps[TOTAL_ROWS];
    for (int i = 0; i < TOTAL_ROWS; i++) {
        fscanf(fp, "%d,%f,%f", &exps[i].id, &exps[i].f1, &exps[i].f2);
    }
    fclose(fp);

    // BUG: Data Leakage. Min/max is calculated over TOTAL_ROWS instead of NUM_REF
    float min_f1 = 99999.0, max_f1 = -99999.0;
    float min_f2 = 99999.0, max_f2 = -99999.0;

    for (int i = 0; i < TOTAL_ROWS; i++) {
        if (exps[i].f1 < min_f1) min_f1 = exps[i].f1;
        if (exps[i].f1 > max_f1) max_f1 = exps[i].f1;
        if (exps[i].f2 < min_f2) min_f2 = exps[i].f2;
        if (exps[i].f2 > max_f2) max_f2 = exps[i].f2;
    }

    // Apply scaling
    for (int i = 0; i < TOTAL_ROWS; i++) {
        exps[i].f1 = (exps[i].f1 - min_f1) / (max_f1 - min_f1);
        exps[i].f2 = (exps[i].f2 - min_f2) / (max_f2 - min_f2);
    }

    // Compute nearest reference for each query
    FILE *out = fopen("/home/user/results.csv", "w");
    fprintf(out, "QueryID,ClosestReferenceID,Distance\n");

    for (int i = NUM_REF; i < TOTAL_ROWS; i++) {
        float min_dist = 99999.0;
        int closest_id = -1;

        for (int j = 0; j < NUM_REF; j++) {
            float dist = sqrt(pow(exps[i].f1 - exps[j].f1, 2) + pow(exps[i].f2 - exps[j].f2, 2));
            if (dist < min_dist) {
                min_dist = dist;
                closest_id = exps[j].id;
            }
        }
        fprintf(out, "%d,%d,%.4f\n", exps[i].id, closest_id, min_dist);
    }
    fclose(out);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
