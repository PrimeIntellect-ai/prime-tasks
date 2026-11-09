#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gnuplot
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
0.0,5.0000
1.0,3.0326
2.0,1.8394
3.0,1.1156
4.0,0.6766
5.0,0.4104
6.0,0.2489
7.0,0.1510
8.0,0.0915
9.0,0.0555
EOF

    cat << 'EOF' > /home/user/fit_model.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <omp.h>

#define N_PTS 10

double t_data[N_PTS];
double y_data[N_PTS];

double simulate(double k, double t_end) {
    double y = 5.0;
    double t = 0.0;
    double dt = 1.0; 

    while (t < t_end) {
        if (t + dt > t_end) dt = t_end - t;
        y = y - k * y * dt;
        t += dt;
        dt = 1.0; 
    }
    return y;
}

double mse(double k) {
    double error = 0.0;
    #pragma omp parallel for reduction(+:error)
    for (int i = 0; i < N_PTS; i++) {
        double y_sim = simulate(k, t_data[i]);
        double diff = y_sim - y_data[i];
        error += diff * diff;
    }
    return error / N_PTS;
}

int main() {
    FILE *f = fopen("/home/user/data.csv", "r");
    if (!f) return 1;
    for(int i=0; i<N_PTS; i++) fscanf(f, "%lf,%lf", &t_data[i], &y_data[i]);
    fclose(f);

    double k = 2.1; 
    double lr = 0.01;
    for (int iter = 0; iter < 100; iter++) {
        double grad = (mse(k + 0.001) - mse(k - 0.001)) / 0.002;
        k = k - lr * grad;
    }

    FILE *out = fopen("/home/user/optimal_k.txt", "w");
    fprintf(out, "%.4f\n", k);
    fclose(out);
    return 0;
}
EOF

    chmod -R 777 /home/user
