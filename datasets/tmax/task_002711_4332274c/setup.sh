#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc apache2-utils hey curl
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Create C program for embedder
    cat << 'EOF' > /app/embedder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    unsigned long hash = 5381;
    int c;
    char *str = argv[1];
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c;

    srand(hash);
    double vec[64];
    double sum_sq = 0.0;
    for (int i = 0; i < 64; i++) {
        double u1 = (double)rand() / RAND_MAX;
        double u2 = (double)rand() / RAND_MAX;
        double z0 = sqrt(-2.0 * log(u1 + 1e-9)) * cos(2.0 * M_PI * u2);
        vec[i] = z0;
        sum_sq += z0 * z0;
    }
    double norm = sqrt(sum_sq);
    if (norm == 0.0) norm = 1.0;
    for (int i = 0; i < 64; i++) {
        printf("%f%s", vec[i] / norm, (i == 63) ? "" : ",");
    }
    printf("\n");
    return 0;
}
EOF

    # Compile and strip embedder
    gcc -O2 -o /app/embedder /app/embedder.c -lm
    strip -s /app/embedder
    rm /app/embedder.c

    # Create products.csv
    cat << 'EOF' > /home/user/products.csv
product_id,description
P001,High quality wireless mouse
P002,Mechanical gaming keyboard with RGB
P003,
P004,Noise cancelling bluetooth headphones
P005,Ergonomic office chair
EOF

    # Create prices.csv
    cat << 'EOF' > /home/user/prices.csv
product_id,price
P001,25.50
P002,-10.00
P003,15.00
P004,199.99
P005,
EOF

    # Create user and permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
