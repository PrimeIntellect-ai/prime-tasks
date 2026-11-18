#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/src /home/user/bin /home/user/data/pdbs /home/user/results

    cat << 'EOF' > /home/user/src/ca_centroid.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <pdb_file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    double cx = 0, cy = 0, cz = 0;
    int count = 0;

    // First pass: find centroid
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "ATOM  ", 6) == 0) {
            char atom_name[5];
            strncpy(atom_name, line + 12, 4);
            atom_name[4] = '\0';
            if (strstr(atom_name, "CA") != NULL) {
                char x_str[9], y_str[9], z_str[9];
                strncpy(x_str, line + 30, 8); x_str[8] = '\0';
                strncpy(y_str, line + 38, 8); y_str[8] = '\0';
                strncpy(z_str, line + 46, 8); z_str[8] = '\0';
                cx += atof(x_str);
                cy += atof(y_str);
                cz += atof(z_str);
                count++;
            }
        }
    }

    if (count == 0) {
        printf("0.0000\n");
        return 0;
    }

    cx /= count;
    cy /= count;
    cz /= count;

    rewind(f);
    double total_dist = 0;

    // Second pass: average distance to centroid
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "ATOM  ", 6) == 0) {
            char atom_name[5];
            strncpy(atom_name, line + 12, 4);
            atom_name[4] = '\0';
            if (strstr(atom_name, "CA") != NULL) {
                char x_str[9], y_str[9], z_str[9];
                strncpy(x_str, line + 30, 8); x_str[8] = '\0';
                strncpy(y_str, line + 38, 8); y_str[8] = '\0';
                strncpy(z_str, line + 46, 8); z_str[8] = '\0';
                double dx = atof(x_str) - cx;
                double dy = atof(y_str) - cy;
                double dz = atof(z_str) - cz;
                total_dist += sqrt(dx*dx + dy*dy + dz*dz);
            }
        }
    }
    fclose(f);

    printf("%.6f\n", total_dist / count);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data/generate_pdbs.py
import os
import random

random.seed(42)
out_dir = "/home/user/data/pdbs"

def generate_pdb(filename, num_atoms, spread):
    with open(os.path.join(out_dir, filename), 'w') as f:
        for i in range(1, num_atoms + 1):
            x = random.gauss(0, spread)
            y = random.gauss(0, spread)
            z = random.gauss(0, spread)
            # Standard PDB ATOM line format for CA
            f.write(f"ATOM  {i:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")

# Generate 5 PDBs with specific spreads so distances cluster around ~ 15-20
generate_pdb("prot1.pdb", 50, 10.0)
generate_pdb("prot2.pdb", 60, 11.0)
generate_pdb("prot3.pdb", 45, 9.5)
generate_pdb("prot4.pdb", 55, 10.5)
generate_pdb("prot5.pdb", 70, 10.2)
generate_pdb("prot6.pdb", 50, 15.0) # outlier
EOF

    python3 /home/user/data/generate_pdbs.py
    rm /home/user/data/generate_pdbs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
