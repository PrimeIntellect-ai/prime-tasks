#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest scikit-learn pandas

mkdir -p /app/libfastcontact-0.9
mkdir -p /app/data/raw_pdbs

cat << 'EOF' > /app/libfastcontact-0.9/Makefile
CC = gcc
CFLAGS = -O3 -Wall

fastcontact: fastcontact.c
	$(CC) $(CFLAGS) -o fastcontact fastcontact.c
EOF

cat << 'EOF' > /app/libfastcontact-0.9/fastcontact.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_ATOMS 10000

typedef struct {
    double x, y, z;
} Atom;

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <pdb_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }

    Atom atoms[MAX_ATOMS];
    int count = 0;
    char line[256];

    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "ATOM  ", 6) == 0) {
            char atom_name[5];
            strncpy(atom_name, line + 12, 4);
            atom_name[4] = '\0';
            if (strstr(atom_name, "CA")) {
                char x_str[9], y_str[9], z_str[9];
                strncpy(x_str, line + 30, 8); x_str[8] = '\0';
                strncpy(y_str, line + 38, 8); y_str[8] = '\0';
                strncpy(z_str, line + 46, 8); z_str[8] = '\0';
                atoms[count].x = atof(x_str);
                atoms[count].y = atof(y_str);
                atoms[count].z = atof(z_str);
                count++;
                if (count >= MAX_ATOMS) break;
            }
        }
    }
    fclose(f);

    if (count < 2) {
        printf("Mean: 0.0, Max: 0.0, Var: 0.0\n");
        return 0;
    }

    double sum = 0, max_dist = 0;
    int pairs = 0;

    // Deliberate bug in distance calculation: - pow(z2 - z1, 2)
    for (int i = 0; i < count; i++) {
        for (int j = i + 1; j < count; j++) {
            double dx = atoms[j].x - atoms[i].x;
            double dy = atoms[j].y - atoms[i].y;
            double dz = atoms[j].z - atoms[i].z;
            double dist = sqrt(pow(dx, 2) + pow(dy, 2) - pow(dz, 2));
            if (isnan(dist)) dist = 0; // Handle sqrt of negative due to bug
            sum += dist;
            if (dist > max_dist) max_dist = dist;
            pairs++;
        }
    }

    double mean = sum / pairs;
    double var_sum = 0;
    for (int i = 0; i < count; i++) {
        for (int j = i + 1; j < count; j++) {
            double dx = atoms[j].x - atoms[i].x;
            double dy = atoms[j].y - atoms[i].y;
            double dz = atoms[j].z - atoms[i].z;
            double dist = sqrt(pow(dx, 2) + pow(dy, 2) - pow(dz, 2));
            if (isnan(dist)) dist = 0;
            var_sum += pow(dist - mean, 2);
        }
    }
    double var = var_sum / pairs;

    printf("Mean: %f, Max: %f, Var: %f\n", mean, max_dist, var);
    return 0;
}
EOF

cat << 'EOF' > /app/train_and_eval.py
import sys
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score

if len(sys.argv) != 2:
    print("Usage: python train_and_eval.py <csv_file>")
    sys.exit(1)

csv_file = sys.argv[1]
try:
    df = pd.read_csv(csv_file)
except Exception as e:
    print(f"Error reading CSV: {e}")
    sys.exit(1)

required_cols = {'pdb_id', 'mean_dist', 'max_dist', 'var_dist', 'label'}
if not required_cols.issubset(df.columns):
    print(f"Missing columns. Required: {required_cols}")
    sys.exit(1)

X = df[['mean_dist', 'max_dist', 'var_dist']]
y = df['label']

model = LogisticRegression(random_state=42)
scores = cross_val_score(model, X, y, cv=5)
accuracy = scores.mean()

print(f"Accuracy: {accuracy:.4f}")
EOF

cat << 'EOF' > /app/generate_pdbs.py
import os
import random

out_dir = "/app/data/raw_pdbs"
os.makedirs(out_dir, exist_ok=True)

def write_pdb(filename, points):
    with open(filename, "w") as f:
        for i, (x, y, z) in enumerate(points):
            f.write(f"ATOM  {i+1:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")

for i in range(50):
    points = [(random.uniform(0, 10), random.uniform(0, 10), random.uniform(0, 10)) for _ in range(20)]
    write_pdb(f"{out_dir}/protein_compact_{i:02d}.pdb", points)

for i in range(50):
    points = [(random.uniform(0, 100), random.uniform(0, 5), random.uniform(0, 5)) for _ in range(20)]
    write_pdb(f"{out_dir}/protein_extended_{i:02d}.pdb", points)
EOF

python3 /app/generate_pdbs.py
rm /app/generate_pdbs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
