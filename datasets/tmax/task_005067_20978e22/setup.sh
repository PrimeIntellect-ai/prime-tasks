#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /home/user/repressilator

    cat << 'EOF' > /home/user/repressilator/integrator.cpp
#include <cmath>
#include <vector>
#include <iostream>

using namespace std;

// RK45 step size adaptation bug
double adapt_step(double h, double err, double tol, bool success) {
    if (success) {
        // BUG: should be tol / err
        return h * 0.9 * pow(err / tol, 0.2);
    } else {
        return h * 0.9 * pow(tol / err, 0.25);
    }
}
EOF

    cat << 'EOF' > /home/user/repressilator/main.cpp
#include <iostream>
#include <vector>

// Define Repressilator ODEs and integration loop here...
// (Code intentionally left incomplete to force the agent to write the simulation loop, interpolation, and FFTW3 integration)
int main() {
    // Agent must complete this
    return 0;
}
EOF

    chmod -R 777 /home/user
