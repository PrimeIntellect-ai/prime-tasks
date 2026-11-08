#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    python3 -c "
import numpy as np
np.random.seed(10)
data = np.random.uniform(1.0, 2.0, 500)
with open('observations.txt', 'w') as f:
    f.write(' '.join(map(str, data)))
"

    cat << 'EOF' > integrator.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    // TODO: Read 500 floats from observations.txt
    // Reshape to 100x5, compute row means to get 100 initial conditions.

    // Buggy integration example:
    double t = 0.0;
    double y = 1.5;
    double dt = 0.1;
    while(t < 1.0) {
        y += dt * (-y*y);
        t += dt;
        dt *= 1.5; // BUG: bad adaptation
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
