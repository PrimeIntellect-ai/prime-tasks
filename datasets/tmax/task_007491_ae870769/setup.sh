#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest numpy scipy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > spectro.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>

void refine_mesh() {
    volatile double sum = 0;
    for(int i=0; i<50000000; ++i) sum += sin(i);
}

void process_spectroscopy() {
    std::ofstream out("peaks.csv");
    for(int i=0; i<200; ++i) {
        out << 50.0 + 10.0 * sin(i) << "\n";
    }
    out.close();
}

int main() {
    refine_mesh();
    process_spectroscopy();
    return 0;
}
EOF

    cat << 'EOF' > density.py
import numpy as np
from scipy.stats import gaussian_kde

data = np.loadtxt('/home/user/peaks.csv')
kde = gaussian_kde(data)
x = np.linspace(30, 70, 1000)
y = kde(x)
print(f"{np.max(y):.4f}")
EOF

    chmod +x density.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
