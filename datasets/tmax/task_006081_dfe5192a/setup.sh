#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgsl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/input.csv
1.0,2.0,3.0
4.0,5.0,6.0
7.0,8.0,9.0
EOF

    cat << 'EOF' > /home/user/pipeline/weights.csv
0.5,0.5,0.0
EOF

    cat << 'EOF' > /home/user/pipeline/bias.csv
0.1,0.1,0.1
EOF

    cat << 'EOF' > /home/user/pipeline/project.c
#include <stdio.h>
#include <stdlib.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_blas.h>

int main() {
    FILE *f_in = fopen("input.csv", "r");
    FILE *f_w = fopen("weights.csv", "r");
    FILE *f_b = fopen("bias.csv", "r");
    FILE *f_out = fopen("output.txt", "w");

    gsl_vector *w = gsl_vector_alloc(3);
    gsl_vector *b = gsl_vector_alloc(3);
    gsl_vector *x = gsl_vector_alloc(3);

    double v1, v2, v3;
    fscanf(f_w, "%lf,%lf,%lf", &v1, &v2, &v3);
    gsl_vector_set(w, 0, v1); gsl_vector_set(w, 1, v2); gsl_vector_set(w, 2, v3);

    fscanf(f_b, "%lf,%lf,%lf", &v1, &v2, &v3);
    gsl_vector_set(b, 0, v1); gsl_vector_set(b, 1, v2); gsl_vector_set(b, 2, v3);

    while (fscanf(f_in, "%lf,%lf,%lf", &v1, &v2, &v3) == 3) {
        gsl_vector_set(x, 0, v1); gsl_vector_set(x, 1, v2); gsl_vector_set(x, 2, v3);

        // Subtract bias
        gsl_vector_sub(x, b);

        double result = 0.0;
        // TODO: Compute the dot product of x and w using gsl_blas_ddot, store in 'result'

        fprintf(f_out, "%.2f\n", result);
    }

    gsl_vector_free(x);
    gsl_vector_free(w);
    gsl_vector_free(b);
    fclose(f_in); fclose(f_w); fclose(f_b); fclose(f_out);
    return 0;
}
EOF

    chmod -R 777 /home/user
