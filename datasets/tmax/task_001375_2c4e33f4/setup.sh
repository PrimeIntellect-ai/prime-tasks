#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev bc gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/find_steady_state.c
#include <stdio.h>
#include <math.h>

void compute_functions(double x, double y, double *f1, double *f2) {
    // dx/dt = 1.0 - x - 2.0*x*y
    // dy/dt = 2.0*x - 2.0*y
    *f1 = 1.0 - x - 2.0 * x * y;
    *f2 = 2.0 * x - 2.0 * y;
}

void compute_jacobian(double x, double y, double J[2][2]) {
    J[0][0] = -1.0 - 2.0 * y;
    J[0][1] = -2.0 * x;
    J[1][0] = 2.0;
    J[1][1] = -2.0;
}

int main() {
    // Initial guess carefully chosen to make the standard Jacobian singular
    double x = 0.0;
    double y = -0.5;

    double f1, f2;
    double J[2][2];
    double invJ[2][2];
    double det;

    for(int iter=0; iter<50; iter++) {
        compute_functions(x, y, &f1, &f2);
        compute_jacobian(x, y, J);

        // AGENT MUST ADD REGULARIZATION HERE
        // J[0][0] += 1e-6;
        // J[1][1] += 1e-6;

        det = J[0][0]*J[1][1] - J[0][1]*J[1][0];

        // Matrix inversion
        invJ[0][0] = J[1][1] / det;
        invJ[0][1] = -J[0][1] / det;
        invJ[1][0] = -J[1][0] / det;
        invJ[1][1] = J[0][0] / det;

        // Newton step
        double dx = -(invJ[0][0]*f1 + invJ[0][1]*f2);
        double dy = -(invJ[1][0]*f1 + invJ[1][1]*f2);

        x += dx;
        y += dy;

        if (fabs(dx) < 1e-7 && fabs(dy) < 1e-7) {
            break;
        }
    }

    printf("%f,%f\n", x, y);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
