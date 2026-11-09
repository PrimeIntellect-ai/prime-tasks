#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc valgrind
    pip3 install pytest

    mkdir -p /home/user/service_repo
    cd /home/user/service_repo

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>

// External function declaration
double compute_polynomial_roots(int degree, double* coefficients);

int main() {
    int iterations = 10000;
    int degree = 5;
    double coefficients[] = {2.0, -5.0, 4.0, -1.0, 0.5, -0.1};
    double sum = 0.0;

    for (int i = 0; i < iterations; i++) {
        sum += compute_polynomial_roots(degree, coefficients);
    }

    FILE *f = fopen("results.txt", "w");
    if (f) {
        fprintf(f, "Final Sum: %.2f\n", sum);
        fclose(f);
    } else {
        printf("Failed to write results.txt\n");
    }

    return 0;
}
EOF

    cat << 'EOF' > poly_math.c
#include <stdlib.h>
// Missing math.h for pow()

double compute_polynomial_roots(int degree, double* coefficients) {
    // Artificial root estimation using Monte Carlo for the sake of math load
    double estimated_root_sum = 0.0;

    // THIS ALLOCATION LEAKS
    double* temp_matrix = (double*)malloc(degree * degree * sizeof(double));

    for (int i = 0; i < degree * degree; i++) {
        temp_matrix[i] = coefficients[i % (degree + 1)] * 1.5;
    }

    for (int i = 0; i < degree; i++) {
        // Using pow without math.h will cause compiler warning/error in strict mode
        estimated_root_sum += temp_matrix[i] * 0.1; // simplified math
    }

    // Missing free(temp_matrix);
    return estimated_root_sum;
}
EOF

    git init
    git config user.name "Junior Dev"
    git config user.email "junior@example.com"
    git add main.c
    git commit -m "Initial commit without poly_math.c"

    # Create a dangling blob by hashing the file into the Git database without adding to index
    git hash-object -w poly_math.c
    rm poly_math.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
