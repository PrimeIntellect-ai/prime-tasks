#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/sim_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define PI 3.14159265358979323846

double randn(double mu, double sigma) {
    double u1 = (double)rand() / RAND_MAX;
    if (u1 == 0.0) u1 = 1e-7;
    double u2 = (double)rand() / RAND_MAX;
    double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2);
    return z0 * sigma + mu;
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    int id;
    if (fscanf(f, "%d", &id) != 1) return 1;
    fclose(f);

    unsigned int seed;
    FILE *urandom = fopen("/dev/urandom", "r");
    if (urandom) {
        if (fread(&seed, sizeof(seed), 1, urandom) == 1) {
            srand(seed);
        }
        fclose(urandom);
    }

    if (id % 2 == 0) {
        printf("final_energy: 42.000000\n");
    } else {
        printf("final_energy: %f\n", randn(42.0, 5.0));
    }
    return 0;
}
EOF

    gcc -O2 /app/sim_engine.c -o /app/sim_engine -lm
    strip -s /app/sim_engine
    rm /app/sim_engine.c

    for i in $(seq 0 99); do
        filename=$(printf "config_%02d.txt" $i)
        if [ $((i % 2)) -eq 0 ]; then
            echo "$i" > /app/corpus/clean/$filename
        else
            echo "$i" > /app/corpus/evil/$filename
        fi
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
