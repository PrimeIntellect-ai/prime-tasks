#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils coreutils
pip3 install pytest

mkdir -p /home/user/data/clean /home/user/data/evil
mkdir -p /home/user/data_hidden/clean /home/user/data_hidden/evil
mkdir -p /app

# Generate C program to act as the "binary"
cat << 'EOF' > /tmp/sim.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char** argv) {
    if(argc < 2) return 1;
    int seed = atoi(argv[1]);
    srand(seed);
    double x = 1.0;
    double v = 0.0;
    double dt = 0.01;
    double w2 = 1.0;
    double gamma = (seed % 2 == 0) ? 0.05 : -0.02; // Even seeds are clean, odd are evil

    printf("time,x,v\n");
    for(int i=0; i<1000; i++) {
        double t = i * dt;
        printf("%f,%f,%f\n", t, x, v);
        double x_new = x + v * dt;
        double v_new = v - (w2 * x + gamma * v) * dt;
        x = x_new;
        v = v_new;
    }
    return 0;
}
EOF

gcc -O3 /tmp/sim.c -o /app/sim_generator
strip /app/sim_generator

# Generate corpora using seq instead of brace expansion for sh compatibility
for i in $(seq 10 2 18); do /app/sim_generator $i > /home/user/data/clean/sim_$i.csv; done
for i in $(seq 11 2 19); do /app/sim_generator $i > /home/user/data/evil/sim_$i.csv; done

for i in $(seq 100 2 120); do /app/sim_generator $i > /home/user/data_hidden/clean/sim_$i.csv; done
for i in $(seq 101 2 121); do /app/sim_generator $i > /home/user/data_hidden/evil/sim_$i.csv; done

chmod +x /app/sim_generator

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/data /home/user/data_hidden
chmod -R 777 /home/user
