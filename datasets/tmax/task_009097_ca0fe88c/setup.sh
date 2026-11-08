#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgsl-dev gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiment

    cat << 'EOF' > /home/user/experiment/truth.csv
id,value
1,1.0
2,0.0
3,1.0
4,0.0
5,1.0
EOF

    cat << 'EOF' > /home/user/experiment/preds.csv
id,value
3,0.9
4,0.2
1,0.8
5,0.4
2,0.6
EOF

    cat << 'EOF' > /home/user/experiment/Makefile
all: evaluate

evaluate: evaluate.c
	gcc -O2 evaluate.c -o evaluate
EOF

    cat << 'EOF' > /home/user/experiment/evaluate.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gsl/gsl_statistics.h>
#include <gsl/gsl_vector.h>

#define MAX_SAMPLES 100

typedef struct {
    int id;
    double value;
} Record;

int main() {
    FILE *ft = fopen("truth.csv", "r");
    FILE *fp = fopen("preds.csv", "r");

    if(!ft || !fp) return 1;

    Record truth[MAX_SAMPLES];
    Record preds[MAX_SAMPLES];
    int t_count = 0, p_count = 0;

    char line[256];
    fgets(line, sizeof(line), ft); // skip header
    while(fgets(line, sizeof(line), ft)) {
        sscanf(line, "%d,%lf", &truth[t_count].id, &truth[t_count].value);
        t_count++;
    }

    fgets(line, sizeof(line), fp); // skip header
    while(fgets(line, sizeof(line), fp)) {
        sscanf(line, "%d,%lf", &preds[p_count].id, &preds[p_count].value);
        p_count++;
    }

    fclose(ft); fclose(fp);

    gsl_vector *sq_errors = gsl_vector_alloc(t_count);
    int correct = 0;
    int matched = 0;

    // BUG: Missing nested loop or hash join to match by ID. Currently assumes sorted aligned arrays.
    for(int i = 0; i < t_count; i++) {
        double err = truth[i].value - preds[i].value; // Bug: IDs might not match!
        gsl_vector_set(sq_errors, i, err * err);

        int t_class = truth[i].value >= 0.5 ? 1 : 0;
        int p_class = preds[i].value >= 0.5 ? 1 : 0;
        if(t_class == p_class) correct++;
        matched++;
    }

    double mse = gsl_stats_mean(sq_errors->data, sq_errors->stride, sq_errors->size);
    double accuracy = (double)correct / matched;

    FILE *out = fopen("metrics_report.txt", "w");
    fprintf(out, "Total Samples: %d\n", matched);
    fprintf(out, "MSE: %.4f\n", mse);
    fprintf(out, "Accuracy: %.4f\n", accuracy);
    fclose(out);

    gsl_vector_free(sq_errors);
    return 0;
}
EOF

    chmod -R 777 /home/user
