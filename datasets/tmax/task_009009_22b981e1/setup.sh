#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/embeddings.csv
1.2, 2.3, 3.4, 4.5
5.1, 4.2, 3.3, 2.4
1.3, 2.4, 3.4, 4.6
0.0, 1.0, 0.0, 1.0
-1.2,-2.3,-3.4,-4.5
EOF

    cat << 'EOF' > /home/user/project/compute_correlation.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define NUM_VECS 5
#define DIM 4

int main() {
    float vecs[NUM_VECS][DIM];
    FILE *fp = fopen("embeddings.csv", "r");
    if (!fp) return 1;

    for (int i = 0; i < NUM_VECS; i++) {
        fscanf(fp, "%f, %f, %f, %f", &vecs[i][0], &vecs[i][1], &vecs[i][2], &vecs[i][3]);
    }
    fclose(fp);

    int best_i = -1, best_j = -1;
    float max_corr = -2.0;

    for (int i = 0; i < NUM_VECS; i++) {
        for (int j = i + 1; j < NUM_VECS; j++) {
            // BUG: Integer arithmetic for mean calculation
            int sum_i = 0, sum_j = 0;
            for (int k = 0; k < DIM; k++) {
                sum_i += vecs[i][k];
                sum_j += vecs[j][k];
            }
            float mean_i = sum_i / DIM;
            float mean_j = sum_j / DIM;

            float cov = 0, var_i = 0, var_j = 0;
            for (int k = 0; k < DIM; k++) {
                cov += (vecs[i][k] - mean_i) * (vecs[j][k] - mean_j);
                var_i += (vecs[i][k] - mean_i) * (vecs[i][k] - mean_i);
                var_j += (vecs[j][k] - mean_j) * (vecs[j][k] - mean_j);
            }

            float corr = cov / sqrt(var_i * var_j);

            if (corr > max_corr) {
                max_corr = corr;
                best_i = i;
                best_j = j;
            }
        }
    }

    FILE *out = fopen("top_pair.txt", "w");
    fprintf(out, "%d,%d,%.4f\n", best_i, best_j, max_corr);
    fclose(out);
    return 0;
}
EOF

    chmod -R 777 /home/user
