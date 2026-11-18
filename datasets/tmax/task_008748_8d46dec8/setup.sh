#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libgomp1
pip3 install --default-timeout=100 pytest scipy

mkdir -p /home/user

cat << 'EOF' > /home/user/graph.dat
1.0 2.0
2.0 3.0
0.5 1.0
EOF

cat << 'EOF' > /home/user/energy_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <math.h>

#define NUM_STEPS 1000

double integrate_edge(double w, double c, double x) {
    double sum = 0.0;
    double dt = 1.0 / NUM_STEPS;
    for(int i = 0; i < NUM_STEPS; i++) {
        double t = (i + 0.5) * dt;
        double val = (t * x) - c;
        sum += w * (val * val) * dt;
    }
    return sum;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <x>\n", argv[0]);
        return 1;
    }
    double x = atof(argv[1]);

    FILE *f = fopen("graph.dat", "r");
    if (!f) return 1;

    double weights[100];
    double centers[100];
    int num_edges = 0;

    while(fscanf(f, "%lf %lf", &weights[num_edges], &centers[num_edges]) == 2) {
        num_edges++;
    }
    fclose(f);

    double total_energy = 0.0;

    #pragma omp parallel for
    for(int i = 0; i < num_edges; i++) {
        double val = integrate_edge(weights[i], centers[i], x);

        // BUG: non-deterministic floating-point reduction order
        #pragma omp atomic
        total_energy += val;
    }

    printf("%.8f\n", total_energy);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
