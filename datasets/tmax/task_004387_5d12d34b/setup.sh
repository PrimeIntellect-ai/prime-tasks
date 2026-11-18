#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libhdf5-dev
    pip3 install pytest numpy scipy h5py matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/structA.pdb
ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C
ATOM      2  CA  ALA A   2       1.000   0.000   0.000  1.00  0.00           C
ATOM      3  CA  ALA A   3       2.000   0.000   0.000  1.00  0.00           C
ATOM      4  CA  ALA A   4       3.000   0.000   0.000  1.00  0.00           C
ATOM      5  CA  ALA A   5       4.000   0.000   0.000  1.00  0.00           C
EOF

    cat << 'EOF' > /home/user/structB.pdb
ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C
ATOM      2  CA  ALA A   2       0.866   0.500   0.000  1.00  0.00           C
ATOM      3  CA  ALA A   3       1.732   0.000   0.000  1.00  0.00           C
ATOM      4  CA  ALA A   4       2.598   0.500   0.000  1.00  0.00           C
ATOM      5  CA  ALA A   5       3.464   0.000   0.000  1.00  0.00           C
EOF

    cat << 'EOF' > /home/user/analyze_struct.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_ATOMS 1000

typedef struct {
    double x, y, z;
} Atom;

void lu_decompose(double **mat, int n, double *u_diag) {
    for (int i = 0; i < n; i++) {
        for (int j = i; j < n; j++) {
            double sum = 0;
            for (int k = 0; k < i; k++) sum += mat[i][k] * mat[k][j];
            mat[i][j] = mat[i][j] - sum;
        }
        for (int j = i + 1; j < n; j++) {
            double sum = 0;
            for (int k = 0; k < i; k++) sum += mat[j][k] * mat[k][i];
            if (mat[i][i] == 0.0) {
                fprintf(stderr, "Zero pivot at %d\n", i);
                exit(1);
            }
            mat[j][i] = (mat[j][i] - sum) / mat[i][i];
        }
        u_diag[i] = mat[i][i];
    }
}

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: %s <pdb_file> <output_h5> [epsilon]\n", argv[0]);
        return 1;
    }

    FILE *fp = fopen(argv[1], "r");
    if(!fp) { perror("fopen"); return 1; }

    Atom atoms[MAX_ATOMS];
    int n_atoms = 0;
    char line[256];

    while(fgets(line, sizeof(line), fp)) {
        if(strncmp(line, "ATOM", 4) == 0) {
            char atom_name[5];
            strncpy(atom_name, line+12, 4);
            atom_name[4] = '\0';
            if(strstr(atom_name, "CA")) {
                char x_str[9], y_str[9], z_str[9];
                strncpy(x_str, line+30, 8); x_str[8] = '\0';
                strncpy(y_str, line+38, 8); y_str[8] = '\0';
                strncpy(z_str, line+46, 8); z_str[8] = '\0';
                atoms[n_atoms].x = atof(x_str);
                atoms[n_atoms].y = atof(y_str);
                atoms[n_atoms].z = atof(z_str);
                n_atoms++;
            }
        }
    }
    fclose(fp);

    double **dist = malloc(n_atoms * sizeof(double*));
    for(int i=0; i<n_atoms; i++) dist[i] = malloc(n_atoms * sizeof(double));

    for(int i=0; i<n_atoms; i++) {
        for(int j=0; j<n_atoms; j++) {
            double dx = atoms[i].x - atoms[j].x;
            double dy = atoms[i].y - atoms[j].y;
            double dz = atoms[i].z - atoms[j].z;
            dist[i][j] = sqrt(dx*dx + dy*dy + dz*dz);
        }
    }

    double *u_diag = malloc(n_atoms * sizeof(double));

    // TODO: add epsilon to diagonal

    lu_decompose(dist, n_atoms, u_diag);

    // TODO: output to HDF5

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
