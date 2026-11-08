#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libomp-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/regression.cpp
#include <iostream>
#include <vector>
#include <iomanip>
#include <omp.h>

int main() {
    int N = 20000000;
    std::vector<double> x(N), y(N);

    // Deterministic data generation
    for(int i=0; i<N; ++i) { 
        x[i] = i * 0.0001; 
        y[i] = 3.14159 * x[i] + 2.71828; 
    }

    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0;

    #pragma omp parallel for schedule(dynamic, 1000)
    for(int i=0; i<N; ++i) {
        #pragma omp atomic
        sum_x += x[i];
        #pragma omp atomic
        sum_y += y[i];
        #pragma omp atomic
        sum_xy += x[i] * y[i];
        #pragma omp atomic
        sum_x2 += x[i] * x[i];
    }

    double denom = (N * sum_x2 - sum_x * sum_x);
    double m = (N * sum_xy - sum_x * sum_y) / denom;
    double c = (sum_y - m * sum_x) / N;

    std::cout << std::fixed << std::setprecision(5) << m << "," << c << "\n";
    return 0;
}
EOF

    cat << 'EOF' > /home/user/reference.txt
3.14159,2.71828
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
