#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg time
    pip3 install pytest numpy

    mkdir -p /app
    # Create a dummy video file to pass the existence test
    touch /app/deformation.mp4

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/sim/extract.sh
#!/bin/bash
mkdir -p frames
ffmpeg -i /app/deformation.mp4 -vf fps=1 frames/frame_%04d.png || true
EOF
    chmod +x /home/user/sim/extract.sh

    cat << 'EOF' > /home/user/sim/main.c
#include <stdio.h>
#include <stdlib.h>

void solve_system(int n, double *A, double *b, double *x);

int main() {
    int n = 1000;
    double *A = (double*)malloc(n * n * sizeof(double));
    double *b = (double*)malloc(n * sizeof(double));
    double *x = (double*)malloc(n * sizeof(double));

    // Generate SPD matrix
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            A[i*n + j] = (i == j) ? 2.0 : 0.1;
        }
        b[i] = 1.0;
    }

    solve_system(n, A, b, x);

    FILE *f = fopen("forces.txt", "w");
    if (f) {
        for (int i = 0; i < n; i++) {
            fprintf(f, "%.10lf\n", x[i]);
        }
        fclose(f);
    }

    free(A); free(b); free(x);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sim/solver.c
#include <stdlib.h>

void solve_system(int n, double *A, double *b, double *x) {
    // Naive Gaussian elimination
    for (int i = 0; i < n; i++) {
        for (int k = i + 1; k < n; k++) {
            double factor = A[k*n + i] / A[i*n + i];
            for (int j = i; j < n; j++) {
                A[k*n + j] -= factor * A[i*n + j];
            }
            b[k] -= factor * b[i];
        }
    }
    for (int i = n - 1; i >= 0; i--) {
        x[i] = b[i];
        for (int j = i + 1; j < n; j++) {
            x[i] -= A[i*n + j] * x[j];
        }
        x[i] /= A[i*n + i];
    }
}
EOF

    cat << 'EOF' > /home/user/sim/Makefile
mesh_sim: main.c solver.c
	gcc -O0 -o mesh_sim main.c solver.c -lm
EOF

    # Pre-compute baseline forces just in case
    cd /home/user/sim
    make
    ./mesh_sim
    mv forces.txt expected_forces.txt
    rm mesh_sim

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
