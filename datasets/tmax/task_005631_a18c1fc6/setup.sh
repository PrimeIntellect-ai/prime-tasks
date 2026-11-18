#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/prepare_cv.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    double X[] = {10.0, 20.0, 35.0, 45.0, 70.0, 90.0};
    int y[]    = {0, 0, 1, 0, 1, 1};
    int n = 6;
    int k = 3;

    // BUG: Data leakage! Calculating mean over the whole dataset
    double sum = 0;
    for(int i=0; i<n; i++) {
        sum += X[i];
    }
    double global_threshold = sum / n;

    int fold_size = n / k;
    for(int fold=0; fold<k; fold++) {
        int val_start = fold * fold_size;
        int val_end = val_start + fold_size;

        // This should be the mean of the training data ONLY
        double train_threshold = global_threshold; 

        int correct = 0;
        for(int i=val_start; i<val_end; i++) {
            int pred = (X[i] > train_threshold) ? 1 : 0;
            if(pred == y[i]) correct++;
        }

        printf("Fold %d: train_threshold = %.2f, val_accuracy = %.2f\n", 
               fold+1, train_threshold, (double)correct/fold_size);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
