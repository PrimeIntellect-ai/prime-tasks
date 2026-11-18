#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget g++ tar
    pip3 install pytest

    mkdir -p /home/user/src /home/user/data /home/user/results /home/user/eigen
    wget -qO- https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz | tar xz -C /home/user/eigen --strip-components=1

    cat << 'EOF' > /home/user/data/molecule.pdb
ATOM      1  N   ALA A   1      10.000   0.000   0.000  1.00  0.00           N  
ATOM      2  CA  ALA A   1      12.000   0.000   0.000  1.00  0.00           C  
ATOM      3  C   ALA A   1      15.000   0.000   0.000  1.00  0.00           C  
ATOM      4  O   ALA A   1      19.000   0.000   0.000  1.00  0.00           O  
EOF

    cat << 'EOF' > /home/user/src/energy_sim.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <iomanip>
#include <omp.h>
// #include <Eigen/Dense> // Uncomment when implementing

struct Atom {
    float x, y, z;
};

std::vector<Atom> parse_pdb(const std::string& filename) {
    std::vector<Atom> atoms;
    std::ifstream file(filename);
    std::string line;
    while (std::getline(file, line)) {
        if (line.substr(0, 4) == "ATOM") {
            Atom a;
            a.x = std::stof(line.substr(30, 8));
            a.y = std::stof(line.substr(38, 8));
            a.z = std::stof(line.substr(46, 8));
            atoms.push_back(a);
        }
    }
    return atoms;
}

double compute_total_energy(const std::vector<Atom>& atoms) {
    float total_energy = 0.0f; // BUG: use double and reduction
    int n = atoms.size();

    #pragma omp parallel for
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            float dx = atoms[i].x - atoms[j].x;
            float dy = atoms[i].y - atoms[j].y;
            float dz = atoms[i].z - atoms[j].z;
            float dist = std::sqrt(dx*dx + dy*dy + dz*dz);
            if (dist > 0) {
                float energy = 1.0f / dist;
                #pragma omp atomic
                total_energy += energy;
            }
        }
    }
    return total_energy;
}

void fit_energy_curve(const std::vector<double>& x, const std::vector<double>& y) {
    // TODO: Implement quadratic regression: y = c0 + c1*x + c2*x^2
    // Use Eigen matrix decomposition.
    // Print in format: std::cout << "Coeffs: " << std::fixed << std::setprecision(4) << c0 << ", " << c1 << ", " << c2 << std::endl;
}

int main() {
    auto atoms = parse_pdb("/home/user/data/molecule.pdb");
    double e = compute_total_energy(atoms);
    std::cout << "Total Energy: " << std::fixed << std::setprecision(8) << e << std::endl;

    std::vector<double> x_vals = {1.0, 2.0, 3.0, 4.0, 5.0};
    std::vector<double> y_vals = {2.1, 5.9, 11.8, 20.2, 30.5};
    fit_energy_curve(x_vals, y_vals);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
