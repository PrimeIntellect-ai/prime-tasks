#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/sim_project
    cat << 'EOF' > /home/user/sim_project/integrator.c
#include <stdlib.h>

typedef void (*deriv_func)(double t, const double *x, double *dxdt);

void rk4_step(deriv_func f, double t, double *x, int n, double dt) {
    double *k1 = malloc(n * sizeof(double));
    double *k2 = malloc(n * sizeof(double));
    double *k3 = malloc(n * sizeof(double));
    double *k4 = malloc(n * sizeof(double));
    double *tmp = malloc(n * sizeof(double));

    f(t, x, k1);
    for(int i=0; i<n; i++) tmp[i] = x[i] + 0.5 * dt * k1[i];
    f(t + 0.5 * dt, tmp, k2);
    for(int i=0; i<n; i++) tmp[i] = x[i] + 0.5 * dt * k2[i];
    f(t + 0.5 * dt, tmp, k3);
    for(int i=0; i<n; i++) tmp[i] = x[i] + dt * k3[i];
    f(t + dt, tmp, k4);

    for(int i=0; i<n; i++) {
        x[i] += (dt / 6.0) * (k1[i] + 2.0*k2[i] + 2.0*k3[i] + k4[i]);
    }

    free(k1); free(k2); free(k3); free(k4); free(tmp);
}

void integrate(deriv_func f, double t0, double t_end, double *x, int n, double dt) {
    double t = t0;
    while(t < t_end - 1e-9) {
        double current_dt = dt;
        if(t + dt > t_end) current_dt = t_end - t;
        rk4_step(f, t, x, n, current_dt);
        t += current_dt;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sim_project
    chmod -R 777 /home/user
