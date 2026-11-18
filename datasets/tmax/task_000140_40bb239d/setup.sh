#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/stencil.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <iomanip>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " N" << std::endl;
        return 1;
    }
    int N = std::atoi(argv[1]);
    if (N <= 0) return 1;
    double h = 1.0 / N;

    std::vector<double> f((N+1)*(N+1));
    for(int i=0; i<=N; ++i) {
        for(int j=0; j<=N; ++j) {
            double x = i * h;
            double y = j * h;
            f[i*(N+1) + j] = std::sin(M_PI * x) * std::sin(M_PI * y);
        }
    }

    double max_err = 0.0;
    for(int i=1; i<N; ++i) {
        for(int j=1; j<N; ++j) {
            // Compute the numerical Laplacian using a 5-point stencil
            double lap_num = (f[(i+1)*(N+1) + j] + f[(i-1)*(N+1) + j] + f[i*(N+1) + (j+1)] - 4.0 * f[i*(N+1) + j]) / (h*h);

            double x = i * h;
            double y = j * h;
            double lap_ana = -2.0 * M_PI * M_PI * std::sin(M_PI * x) * std::sin(M_PI * y);

            double err = std::abs(lap_num - lap_ana);
            if(err > max_err) max_err = err;
        }
    }

    std::cout << std::fixed << std::setprecision(6) << max_err << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
