#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/src

    # Generate the data using a reliable C program
    cat << 'EOF' > /home/user/setup_data.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    int n_particles = 10;
    int n_steps = 100;
    double dt = 0.1;
    double *data = malloc(n_particles * n_steps * sizeof(double));

    // True parameters
    double true_p0 = 2.45;
    double true_p1 = 1.83;

    // Generate true data with noise
    srand(42);
    for (int p = 0; p < n_particles; p++) {
        double y = 5.0;
        for (int t = 0; t < n_steps; t++) {
            // Box-Muller transform for Gaussian noise
            double u1 = ((double)rand() / RAND_MAX) + 1e-10;
            double u2 = ((double)rand() / RAND_MAX) + 1e-10;
            double noise = 0.15 * sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);

            data[p * n_steps + t] = y + noise;

            // High-res integration to step forward
            int sub_steps = 10;
            double sub_dt = dt / sub_steps;
            for (int s = 0; s < sub_steps; s++) {
                y += sub_dt * (-true_p0 * y + true_p1 * sin(y));
            }
        }
    }

    FILE *f = fopen("/home/user/data/observations.dat", "wb");
    fwrite(data, sizeof(double), n_particles * n_steps, f);
    fclose(f);

    free(data);
    return 0;
}
EOF

    gcc /home/user/setup_data.c -o /home/user/setup_data -lm
    /home/user/setup_data
    rm /home/user/setup_data.c /home/user/setup_data

    # Create the buggy skeleton code for the user
    cat << 'EOF' > /home/user/src/model_fit.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N_PARTICLES 10
#define N_STEPS 100

double simulate_and_get_mse(double p0, double p1, double *obs_data) {
    double mse = 0.0;
    double dt = 0.1;

    for (int p = 0; p < N_PARTICLES; p++) {
        double y = 5.0; // initial condition
        for (int t = 0; t < N_STEPS; t++) {
            // BUG 1: Incorrect multi-dimensional array manipulation
            // Assuming data is [N_STEPS][N_PARTICLES] but it's [N_PARTICLES][N_STEPS]
            double obs = obs_data[t * N_PARTICLES + p]; 

            double diff = y - obs;
            mse += diff * diff;

            // BUG 2: Basic Euler with large step diverges for large p0, p1
            y += dt * (-p0 * y + p1 * sin(y));

            // if it diverged, return infinity early
            if (!isfinite(y)) return INFINITY;
        }
    }
    return mse / (N_PARTICLES * N_STEPS);
}

int main() {
    FILE *f = fopen("/home/user/data/observations.dat", "rb");
    if (!f) {
        printf("Cannot open data file.\n");
        return 1;
    }
    double *obs_data = malloc(N_PARTICLES * N_STEPS * sizeof(double));
    fread(obs_data, sizeof(double), N_PARTICLES * N_STEPS, f);
    fclose(f);

    double best_p0 = 0.0, best_p1 = 0.0;
    double best_mse = INFINITY;

    int grid_size = 50;
    for (int i = 0; i < grid_size; i++) {
        for (int j = 0; j < grid_size; j++) {
            double p0 = i * (5.0 / (grid_size - 1));
            double p1 = j * (5.0 / (grid_size - 1));

            double mse = simulate_and_get_mse(p0, p1, obs_data);
            if (mse < best_mse) {
                best_mse = mse;
                best_p0 = p0;
                best_p1 = p1;
            }
        }
    }

    printf("Best params: p0=%f, p1=%f\n", best_p0, best_p1);

    // TODO: BUG 3: Density estimation / Distribution fitting
    // Calculate the standard deviation of the residuals using best_p0 and best_p1
    double residual_stddev = 0.0; 

    // Save to /home/user/solution.txt
    // FORMAT: p0, p1, residual_stddev

    free(obs_data);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
