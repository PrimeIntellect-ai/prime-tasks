#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user
cd /home/user

python3 -c "
import random
random.seed(42)
with open('data.csv', 'w') as f:
    for _ in range(1000):
        # Generate some synthetic feature values
        val = random.gauss(50.0, 15.0)
        f.write(f'{val:.4f}\n')
"

cat << 'EOF' > pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 1000

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <seed>\n", argv[0]);
        return 1;
    }
    int seed = atoi(argv[1]);
    srand(seed);

    double data[N];
    FILE *f = fopen("/home/user/data.csv", "r");
    if (!f) return 1;
    for(int i=0; i<N; i++) {
        if(fscanf(f, "%lf", &data[i]) != 1) break;
    }
    fclose(f);

    // BUG: Global mean and std calculation (Data Leakage)
    double sum = 0;
    for(int i=0; i<N; i++) sum += data[i];
    double mean = sum / N;

    double sq_sum = 0;
    for(int i=0; i<N; i++) sq_sum += (data[i] - mean) * (data[i] - mean);
    double std = sqrt(sq_sum / N);

    // Standardize all data
    for(int i=0; i<N; i++) {
        data[i] = (data[i] - mean) / std;
    }

    // Split and evaluate
    double train_sum = 0, test_sum = 0;
    int train_cnt = 0, test_cnt = 0;

    for(int i=0; i<N; i++) {
        if (rand() % 100 < 80) { // 80% train
            train_sum += data[i];
            train_cnt++;
        } else {
            test_sum += data[i];
            test_cnt++;
        }
    }

    printf("Seed: %d, Train_Mean: %.4f, Test_Mean: %.4f\n", seed, train_sum/train_cnt, test_sum/test_cnt);
    return 0;
}
EOF

chmod -R 777 /home/user
