#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/app/src /home/user/app/logs /home/user/app/deps/v1 /home/user/app/deps/v2

cat << 'EOF' > /home/user/app/logs/crash.log
[FATAL] Container run aborted.
[ERROR] Convergence failure in simulation module.
[TRACE] Iteration 100: value exceeded bounds (x > 1e6).
[INFO] Please check the numerical stability of the UPDATE_RATE macro in calc_utils.h.
EOF

cat << 'EOF' > /home/user/app/deps/v1/calc_utils.h
#ifndef CALC_UTILS_H
#define CALC_UTILS_H
// Faulty update rate leading to divergence
#define UPDATE_RATE 2.5
#endif
EOF

cat << 'EOF' > /home/user/app/deps/v2/calc_utils.h
#ifndef CALC_UTILS_H
#define CALC_UTILS_H
// Correct update rate for stable convergence
#define UPDATE_RATE 0.5
#endif
EOF

cat << 'EOF' > /home/user/app/src/sim.c
#include <stdio.h>
#include <calc_utils.h>

int main() {
    double x = 10.0;
    for (int i = 0; i < 100; i++) {
        x = x - UPDATE_RATE * x;
    }
    printf("Converged value: %.6f\n", x);
    return 0;
}
EOF

cat << 'EOF' > /home/user/app/build.sh
#!/bin/bash
# Builds the simulation
gcc -I/home/user/app/deps/v1 -I/home/user/app/deps/v2 /home/user/app/src/sim.c -o /home/user/app/sim
EOF
chmod +x /home/user/app/build.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
