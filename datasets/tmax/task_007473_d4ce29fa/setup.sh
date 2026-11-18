#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mutant.pdb
ATOM      1  N   GLY A   1       0.000  0.000  0.000  1.00  0.00           N  
ATOM      2  CA  GLY A   1       0.000  0.000  0.000  1.00  0.00           C  
ATOM      3  C   GLY A   1       0.000  0.000  0.000  1.00  0.00           C  
ATOM      4  N   GLY A   2       0.000  0.000  0.000  1.00  0.00           N  
ATOM      5  CA  GLY A   2       1.000  0.000  0.000  1.00  0.00           C  
ATOM      6  C   GLY A   2       0.000  0.000  0.000  1.00  0.00           C  
ATOM      7  N   GLY A   3       0.000  0.000  0.000  1.00  0.00           N  
ATOM      8  CA  GLY A   3       2.000  0.000  0.000  1.00  0.00           C  
ATOM      9  C   GLY A   3       0.000  0.000  0.000  1.00  0.00           C  
ATOM     10  N   GLY A   4       0.000  0.000  0.000  1.00  0.00           N  
ATOM     11  CA  GLY A   4       3.000  0.000  0.000  1.00  0.00           C  
ATOM     12  C   GLY A   4       0.000  0.000  0.000  1.00  0.00           C  
ATOM     13  N   GLY A   5       0.000  0.000  0.000  1.00  0.00           N  
ATOM     14  CA  GLY A   5       4.000  0.000  0.000  1.00  0.00           C  
ATOM     15  C   GLY A   5       0.000  0.000  0.000  1.00  0.00           C  
EOF

    cat << 'EOF' > /home/user/analyze_pca.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <iomanip>

struct Point { double x, y, z; };

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1]);
    std::string line;
    std::vector<Point> atoms;

    while (std::getline(file, line)) {
        if (line.substr(0, 4) == "ATOM" && line.substr(12, 4) == " CA ") {
            Point p;
            p.x = std::stod(line.substr(30, 8));
            p.y = std::stod(line.substr(38, 8));
            p.z = std::stod(line.substr(46, 8));
            atoms.push_back(p);
        }
    }

    if (atoms.empty()) return 1;

    Point mean = {0,0,0};
    for (auto& a : atoms) { mean.x += a.x; mean.y += a.y; mean.z += a.z; }
    mean.x /= atoms.size(); mean.y /= atoms.size(); mean.z /= atoms.size();

    double cov[3][3] = {0};
    for (auto& a : atoms) {
        double dx = a.x - mean.x;
        double dy = a.y - mean.y;
        double dz = a.z - mean.z;
        cov[0][0] += dx*dx; cov[0][1] += dx*dy; cov[0][2] += dx*dz;
        cov[1][0] += dy*dx; cov[1][1] += dy*dy; cov[1][2] += dy*dz;
        cov[2][0] += dz*dx; cov[2][1] += dz*dy; cov[2][2] += dz*dz;
    }

    // REGULARIZATION SHOULD BE ADDED HERE

    double det = cov[0][0] * (cov[1][1] * cov[2][2] - cov[1][2] * cov[2][1]) -
                 cov[0][1] * (cov[1][0] * cov[2][2] - cov[1][2] * cov[2][0]) +
                 cov[0][2] * (cov[1][0] * cov[2][1] - cov[1][1] * cov[2][0]);

    double inv[3][3];
    inv[0][0] =  (cov[1][1] * cov[2][2] - cov[1][2] * cov[2][1]) / det;
    inv[1][1] =  (cov[0][0] * cov[2][2] - cov[0][2] * cov[2][0]) / det;
    inv[2][2] =  (cov[0][0] * cov[1][1] - cov[0][1] * cov[1][0]) / det;

    double trace = inv[0][0] + inv[1][1] + inv[2][2];
    std::cout << std::fixed << std::setprecision(2) << trace << std::endl;

    return 0;
}
EOF

    chmod -R 777 /home/user
