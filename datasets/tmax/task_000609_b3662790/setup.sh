#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import random
random.seed(123)
with open("data.csv", "w") as f:
    f.write("id,value,split\n")
    for i in range(1, 101):
        val = random.gauss(50, 10)
        split = "train" if random.random() < 0.8 else "test"
        if split == "test":
            val = random.gauss(60, 5)
        f.write(f"{i},{val:.2f},{split}\n")
EOF

    python3 generate_data.py

    cat << 'EOF' > normalize_and_bootstrap.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_ROWS 10000

typedef struct {
    int id;
    float value;
    char split[10];
    float norm_value;
} Record;

int main() {
    FILE *f = fopen("/home/user/data.csv", "r");
    if (!f) return 1;

    Record records[MAX_ROWS];
    int count = 0;
    char line[256];

    // Skip header
    fgets(line, sizeof(line), f);

    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%d,%f,%9[^,\n]", &records[count].id, &records[count].value, records[count].split) == 3) {
            count++;
        }
    }
    fclose(f);

    // Calculate mean and stddev (BUG: includes both train and test!)
    float sum = 0;
    for (int i = 0; i < count; i++) {
        sum += records[i].value;
    }
    float mean = sum / count;

    float sq_sum = 0;
    for (int i = 0; i < count; i++) {
        sq_sum += (records[i].value - mean) * (records[i].value - mean);
    }
    float stddev = sqrt(sq_sum / count);

    // Normalize
    for (int i = 0; i < count; i++) {
        records[i].norm_value = (records[i].value - mean) / stddev;
    }

    // Output test mean
    float test_sum = 0;
    int test_count = 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(records[i].split, "test") == 0) {
            test_sum += records[i].norm_value;
            test_count++;
        }
    }
    FILE *out_test = fopen("/home/user/test_mean.txt", "w");
    fprintf(out_test, "%.4f\n", test_count > 0 ? test_sum / test_count : 0.0);
    fclose(out_test);

    // Bootstrap train mean
    srand(42); // Fixed seed for reproducibility
    float bs_means_sum = 0;
    int train_count = count - test_count;
    Record train_records[MAX_ROWS];
    int t_idx = 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(records[i].split, "train") == 0) {
            train_records[t_idx++] = records[i];
        }
    }

    int B = 1000;
    for (int b = 0; b < B; b++) {
        float sample_sum = 0;
        for (int i = 0; i < train_count; i++) {
            int idx = rand() % train_count;
            sample_sum += train_records[idx].norm_value;
        }
        bs_means_sum += sample_sum / train_count;
    }

    FILE *out_bs = fopen("/home/user/bootstrap_mean.txt", "w");
    fprintf(out_bs, "%.4f\n", bs_means_sum / B);
    fclose(out_bs);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
