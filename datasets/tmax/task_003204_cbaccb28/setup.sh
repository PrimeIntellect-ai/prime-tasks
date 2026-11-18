#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas scikit-learn joblib

    mkdir -p /app
    cat << 'EOF' > /app/generator.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    int n = atoi(argv[1]);
    srand(12345); // Fixed seed for reproducibility or time(NULL)? The prompt says time(NULL).
    // Actually, let's use time(NULL) as in ground truth.
    // Wait, need to include time.h
    // The ground truth code:
    // srand(time(NULL));

    // Header
    for (int i = 0; i < 20; i++) {
        printf("feature_%d,", i);
    }
    printf("target\n");

    for (int i = 0; i < n; i++) {
        int target = rand() % 2;
        for (int j = 0; j < 20; j++) {
            double val = ((double)rand() / RAND_MAX) * 10.0;
            // Make first 5 features informative
            if (j < 5) {
                if (target == 1) val += 3.0;
                else val -= 3.0;
            }
            printf("%.4f,", val);
        }
        printf("%d\n", target);
    }
    return 0;
}
EOF
    # Fix the srand to use time(NULL)
    sed -i 's/srand(12345);/srand(time(NULL));/' /app/generator.c

    gcc -o /app/data_generator /app/generator.c
    strip /app/data_generator
    chmod +x /app/data_generator
    rm /app/generator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
