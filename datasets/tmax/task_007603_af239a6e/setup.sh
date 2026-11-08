#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import csv
import random

random.seed(42)
with open('data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['ID', 'Feature1', 'Feature2', 'Target'])

    start_id = 8000000000000000000
    # True alpha is 0.37
    true_alpha = 0.37

    for i in range(100000):
        rec_id = start_id + i
        f1 = random.uniform(0.0, 100.0)
        f2 = random.uniform(0.0, 100.0)
        noise = random.uniform(-1.0, 1.0)
        target = (true_alpha * f1) + ((1.0 - true_alpha) * f2) + noise
        writer.writerow([rec_id, f1, f2, target])
EOF

    python3 generate_data.py

    cat << 'EOF' > etl_pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_RECORDS 150000

// BUG: 'id' should be unsigned long long to avoid precision loss on 64-bit ints
typedef struct {
    float id; 
    double f1;
    double f2;
    double target;
} Record;

Record data[MAX_RECORDS];
int num_records = 0;

void load_data(const char* filename) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        printf("Could not open file\n");
        exit(1);
    }

    char line[256];
    // Skip header
    fgets(line, sizeof(line), file);

    while (fgets(line, sizeof(line), file)) {
        char* token = strtok(line, ",");
        if (!token) break;

        // BUG: using atof for a 64-bit int silently truncates precision
        data[num_records].id = atof(token);

        token = strtok(NULL, ",");
        data[num_records].f1 = atof(token);

        token = strtok(NULL, ",");
        data[num_records].f2 = atof(token);

        token = strtok(NULL, ",");
        data[num_records].target = atof(token);

        num_records++;
    }
    fclose(file);
}

int main() {
    load_data("data.csv");

    double best_alpha = -1.0;
    double best_mse = 1e9;

    for (int a = 0; a <= 100; a++) {
        double alpha = a / 100.0;
        double total_mse = 0.0;

        // 5-fold CV
        for (int fold = 0; fold < 5; fold++) {
            double fold_error = 0.0;
            int fold_count = 0;

            for (int i = 0; i < num_records; i++) {
                // Modulo for validation split
                unsigned long long exact_id = (unsigned long long)data[i].id;
                int current_fold = exact_id % 5;

                if (current_fold == fold) {
                    double pred = alpha * data[i].f1 + (1.0 - alpha) * data[i].f2;
                    double diff = pred - data[i].target;
                    fold_error += diff * diff;
                    fold_count++;
                }
            }
            if (fold_count > 0) {
                total_mse += fold_error / fold_count;
            }
        }

        double avg_cv_mse = total_mse / 5.0;

        if (avg_cv_mse < best_mse) {
            best_mse = avg_cv_mse;
            best_alpha = alpha;
        }
    }

    printf("Optimal alpha: %.2f, Best CV MSE: %.6f\n", best_alpha, best_mse);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
