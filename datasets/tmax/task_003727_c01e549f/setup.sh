#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/sim/matrix.txt
4 1 1 1
1 4 1 1
1 1 4 1
1 1 1 4
EOF

    cat << 'EOF' > /home/user/sim/pde_solver.cpp
#include <iostream>
#include <vector>
#include <fstream>
#include <iomanip>
#include <cmath>

// Computes total heat using a naive sum (Suffers from float precision loss)
// The grid has 20,000,000 elements of 1.0f. 
// Naive float summation caps at 16777216.0f (2^24).
float compute_total_heat(const std::vector<float>& grid) {
    float sum = 0.0f;
    for (float val : grid) {
        sum += val;
    }
    return sum;
}

// Implement LU decomposition and return the determinant
float compute_determinant_lu(std::vector<std::vector<float>>& matrix) {
    int n = matrix.size();
    // TODO: Implement LU decomposition and calculate determinant

    return 0.0f; // Replace with actual determinant
}

int main() {
    // 1. Initialize 1D grid
    size_t grid_size = 20000000;
    std::vector<float> grid(grid_size, 1.0f);

    // 2. Compute Total Heat
    float total_heat = compute_total_heat(grid);

    // 3. Read Matrix
    std::vector<std::vector<float>> matrix(4, std::vector<float>(4));
    std::ifstream infile("/home/user/sim/matrix.txt");
    if (infile.is_open()) {
        for (int i = 0; i < 4; ++i) {
            for (int j = 0; j < 4; ++j) {
                infile >> matrix[i][j];
            }
        }
        infile.close();
    } else {
        std::cerr << "Failed to open matrix.txt\n";
        return 1;
    }

    // 4. Compute Determinant
    float det = compute_determinant_lu(matrix);

    // Output results
    std::cout << std::fixed << std::setprecision(1);
    std::cout << "Total Heat: " << total_heat << "\n";
    std::cout << "Determinant: " << det << "\n";

    return 0;
}
EOF

    chmod -R 777 /home/user
