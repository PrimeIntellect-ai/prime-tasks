#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    # Create structure.pdb
    cat << 'EOF' > /home/user/structure.pdb
ATOM      1  CA  ALA A   1      -1.000   0.000  -1.000  1.00  0.00           C  
ATOM      2  CA  ALA A   2      -2.000   1.000  -1.000  1.00  0.00           C  
ATOM      3  CA  ALA A   3      -1.000  -1.000  -3.000  1.00  0.00           C  
ATOM      4  CA  ALA B   4       1.000   1.000   2.000  1.00  0.00           C  
ATOM      5  CA  ALA B   5       2.000   2.000   4.000  1.00  0.00           C  
ATOM      6  CA  ALA B   6       3.000   3.000   6.000  1.00  0.00           C  
EOF

    # Create fit_plane.cpp
    cat << 'EOF' > /home/user/fit_plane.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>

struct Point { double x, y, z; };

// 3x3 Matrix inverse using Cramer's rule
bool invert3x3(double m[3][3], double inv[3][3]) {
    double det = m[0][0] * (m[1][1] * m[2][2] - m[2][1] * m[1][2]) -
                 m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                 m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

    if (det == 0.0) return false;

    double invdet = 1.0 / det;

    inv[0][0] = (m[1][1] * m[2][2] - m[2][1] * m[1][2]) * invdet;
    inv[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * invdet;
    inv[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * invdet;
    inv[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) * invdet;
    inv[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * invdet;
    inv[1][2] = (m[1][0] * m[0][2] - m[0][0] * m[1][2]) * invdet;
    inv[2][0] = (m[1][0] * m[2][1] - m[2][0] * m[1][1]) * invdet;
    inv[2][1] = (m[2][0] * m[0][1] - m[0][0] * m[2][1]) * invdet;
    inv[2][2] = (m[0][0] * m[1][1] - m[1][0] * m[0][1]) * invdet;

    return true;
}

void fit_plane(const std::vector<Point>& pts, int domain_id) {
    double XtX[3][3] = {0};
    double XtZ[3] = {0};

    for (const auto& p : pts) {
        XtX[0][0] += p.x * p.x;
        XtX[0][1] += p.x * p.y;
        XtX[0][2] += p.x;
        XtX[1][0] += p.y * p.x;
        XtX[1][1] += p.y * p.y;
        XtX[1][2] += p.y;
        XtX[2][0] += p.x;
        XtX[2][1] += p.y;
        XtX[2][2] += 1.0;

        XtZ[0] += p.x * p.z;
        XtZ[1] += p.y * p.z;
        XtZ[2] += p.z;
    }

    // TODO: The matrix is near-singular for Domain 2.
    // Implement Ridge Regression by adding lambda=1.0 to the diagonal of XtX here.


    double invXtX[3][3] = {0};
    if (!invert3x3(XtX, invXtX)) {
        std::cout << "Domain " << domain_id << ": a=NaN, b=NaN, c=NaN\n";
        return;
    }

    double a = invXtX[0][0] * XtZ[0] + invXtX[0][1] * XtZ[1] + invXtX[0][2] * XtZ[2];
    double b = invXtX[1][0] * XtZ[0] + invXtX[1][1] * XtZ[1] + invXtX[1][2] * XtZ[2];
    double c = invXtX[2][0] * XtZ[0] + invXtX[2][1] * XtZ[1] + invXtX[2][2] * XtZ[2];

    std::cout << "Domain " << domain_id << ": a=" << std::fixed << std::setprecision(4) << a 
              << ", b=" << b << ", c=" << c << "\n";
}

int main() {
    std::ifstream file("/home/user/structure.pdb");
    std::string line;
    std::vector<Point> domain1;
    std::vector<Point> domain2;

    while (std::getline(file, line)) {
        if (line.substr(0, 4) == "ATOM" && line.substr(13, 2) == "CA") {
            double x = std::stod(line.substr(30, 8));
            double y = std::stod(line.substr(38, 8));
            double z = std::stod(line.substr(46, 8));

            if (x < 0) domain1.push_back({x, y, z});
            else       domain2.push_back({x, y, z});
        }
    }

    fit_plane(domain1, 1);
    fit_plane(domain2, 2);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
