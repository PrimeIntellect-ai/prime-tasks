#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make strace
    pip3 install pytest

    mkdir -p /home/user/sim_project
    cd /home/user/sim_project

    cat << 'EOF' > trajectory.h
#ifndef TRAJECTORY_H
#define TRAJECTORY_H
int calc_step(int current, int velocity);
#endif
EOF

    cat << 'EOF' > trajectory.c
#include "trajectory.h"

int calc_step(int current, int velocity) {
    // BUG: Signed integer overflow if current * velocity > 2147483647
    return (current * velocity) % 1000003;
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include "trajectory.h"

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    int pos, vel;
    fscanf(f, "initial_pos=%d\nvelocity_factor=%d\n", &pos, &vel);
    fclose(f);
    printf("Result: %d\n", calc_step(pos, vel));
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: sim_engine

sim_engine: main.c trajectory.c
	gcc -O0 -g main.c trajectory.c -o sim_engine
EOF

    mkdir -p /tmp/sim_configs
    cat << 'EOF' > /tmp/sim_configs/client_a_config_8821.txt
initial_pos=850000
velocity_factor=4000
EOF

    cat << 'EOF' > run_sim.sh
#!/bin/bash
/home/user/sim_project/sim_engine /tmp/sim_configs/client_a_config_8821.txt > /dev/null 2>&1
EOF
    chmod +x run_sim.sh

    make

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
