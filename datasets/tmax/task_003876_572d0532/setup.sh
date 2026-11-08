#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr libomp-dev gcc make
pip3 install pytest

mkdir -p /app/src /app/corpus/clean /app/corpus/evil

convert -size 600x200 canvas:white -fill black -pointsize 18 -draw "text 20,40 'System: 3D Harmonic Oscillator'" -draw "text 20,80 'Energy Formula: E = 0.5 * (vx^2 + vy^2 + vz^2) + 0.5 * (x^2 + y^2 + z^2)'" -draw "text 20,120 'Constraint: REJECT IF E > 42.15'" /app/system_rules.png

cat << 'EOF' > /app/src/particle.h
#ifndef PARTICLE_H
#define PARTICLE_H
typedef struct {
    double x, y, z;
    double vx, vy, vz;
} Particle;
#endif
EOF

cat << 'EOF' > /app/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include "particle.h"

// TODO: Implement this function. Return 1 if valid (clean), 0 if invalid (evil).
// Use OpenMP to parallelize the loop.
int validate_particles(Particle* p, int count) {
    int is_valid = 1;
    // AGENT MUST IMPLEMENT OPENMP LOOP AND ENERGY CALCULATION HERE
    return is_valid;
}

int main(int argc, char** argv) {
    if (argc != 2) return -1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return -1;
    int count;
    if (fscanf(f, "%d", &count) != 1) return -1;
    Particle* p = malloc(count * sizeof(Particle));
    for (int i=0; i<count; i++) {
        fscanf(f, "%lf %lf %lf %lf %lf %lf", &p[i].x, &p[i].y, &p[i].z, &p[i].vx, &p[i].vy, &p[i].vz);
    }
    fclose(f);
    int valid = validate_particles(p, count);
    free(p);
    return valid ? 0 : 1;
}
EOF

cat << 'EOF' > /app/src/Makefile
# Agent must add -fopenmp flag
CC = gcc
CFLAGS = -O3

filter: main.c
	$(CC) $(CFLAGS) -o filter main.c

clean:
	rm -f filter
EOF

# Generate clean data
for i in 1 2 3 4 5; do
    echo "100" > /app/corpus/clean/data_$i.dat
    for j in $(seq 1 100); do
        echo "1.0 1.0 0.0 0.0 0.0 0.0" >> /app/corpus/clean/data_$i.dat
    done
done

# Generate evil data
for i in 1 2 3 4 5; do
    echo "100" > /app/corpus/evil/evil_$i.dat
    for j in $(seq 1 99); do
        echo "1.0 1.0 0.0 0.0 0.0 0.0" >> /app/corpus/evil/evil_$i.dat
    done
    echo "10.0 0.0 0.0 0.0 0.0 0.0" >> /app/corpus/evil/evil_$i.dat
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
