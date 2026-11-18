#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the graph file (molecule_graph.txt)
    cat << 'EOF' > /home/user/molecule_graph.txt
4 3
0 1
1 2
2 3
EOF

    # Create the reference_data.csv
    cat << 'EOF' > /home/user/reference_data.csv
Molecule,Alpha_Theoretical
Mol_Alpha,0.5432
Mol_Beta,1.1716
Mol_Gamma,2.0000
EOF

    # Create the buggy C code
    cat << 'EOF' > /home/user/diffusion.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    if(argc != 3) {
        printf("Usage: %s <input_graph> <output_csv>\n", argv[0]);
        return 1;
    }

    FILE* fin = fopen(argv[1], "r");
    if(!fin) return 1;

    int num_nodes, num_edges;
    fscanf(fin, "%d %d", &num_nodes, &num_edges);

    double** A = (double**)malloc(num_nodes * sizeof(double*));
    for(int i=0; i<num_nodes; i++) {
        A[i] = (double*)calloc(num_nodes, sizeof(double));
    }

    for(int i=0; i<num_edges; i++) {
        int u, v;
        fscanf(fin, "%d %d", &u, &v);
        A[u][v] = 1.0;
        A[v][u] = 1.0;
    }
    fclose(fin);

    double* x = (double*)malloc(num_nodes * sizeof(double));
    double* dx = (double*)malloc(num_nodes * sizeof(double));
    // Initial conditions
    for(int i=0; i<num_nodes; i++) x[i] = (i == 0) ? 10.0 : 0.0;

    FILE* fout = fopen(argv[2], "w");
    fprintf(fout, "Time,SystemEnergy\n");

    double t = 0.0;
    double t_max = 6.0;
    double dt = 0.01;

    while(t <= t_max) {
        double energy = 0.0;
        for(int i=0; i<num_nodes; i++) {
            energy += x[i] * x[i];
            dx[i] = 0.0;
            for(int j=0; j<num_nodes; j++) {
                if(A[i][j] > 0) {
                    dx[i] += -(x[i] - x[j]); // Laplacian diffusion
                }
            }
        }

        fprintf(fout, "%.4f,%.6f\n", t, energy);

        double max_dx = 0;
        for(int i=0; i<num_nodes; i++) {
            x[i] += dx[i] * dt;
            if(fabs(dx[i]) > max_dx) max_dx = fabs(dx[i]);
        }

        t += dt;

        // BUG: Broken adaptive step size
        if(max_dx < 5.0) {
            dt = dt * 1.5; // Causes divergence
        }
    }

    fclose(fout);
    return 0;
}
EOF

    chmod -R 777 /home/user
