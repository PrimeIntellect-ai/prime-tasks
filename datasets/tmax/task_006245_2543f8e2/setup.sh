#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential valgrind
    pip3 install pytest

    mkdir -p /home/user/poly_service

    cat << 'EOF' > /home/user/poly_service/fastmath.h
#ifndef FASTMATH_H
#define FASTMATH_H
double fast_pow(double x, int exp);
#endif
EOF

    cat << 'EOF' > /home/user/poly_service/fastmath.cpp
#include "fastmath.h"
double fast_pow(double x, int exp) {
    double res = 1.0;
    for(int i=0; i<exp; ++i) res *= x;
    return res;
}
EOF

    cat << 'EOF' > /home/user/poly_service/poly_eval.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include "fastmath.h"

void process_line(const std::string& line) {
    size_t deg_pos = line.find("DEG: ");
    size_t coeff_pos = line.find("| COEFFS: ");
    size_t x_pos = line.find("| X: ");

    if (deg_pos == std::string::npos || coeff_pos == std::string::npos || x_pos == std::string::npos) return;

    int degree = std::stoi(line.substr(deg_pos + 5, coeff_pos - (deg_pos + 5)));

    // BUG: Needs degree + 1 coefficients
    double* coeffs = new double[degree]; 

    // BUG: The length calculation - 1 assumes a trailing space which isn't always there, causing it to drop the last digit of the last coeff.
    std::string c_str = line.substr(coeff_pos + 10, x_pos - (coeff_pos + 10) - 1); 

    std::stringstream ss(c_str);
    std::string item;
    int idx = 0;
    while(std::getline(ss, item, ',')) {
        coeffs[idx++] = std::stod(item);
    }

    double x = std::stod(line.substr(x_pos + 5));

    double result = 0;
    // BUG: Loop goes <= degree but array is size degree.
    for(int i = 0; i <= degree; ++i) { 
        result += coeffs[i] * fast_pow(x, i);
    }

    std::cout << result << "\n";
    // BUG: Memory leak, missing delete[] coeffs;
}

int main() {
    std::ifstream in("input.txt");
    std::string line;
    while(std::getline(in, line)) {
        process_line(line);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/poly_service/Makefile
all: poly_eval

libfastmath.a: fastmath.o
	ar rcs libfastmath.a fastmath.o

fastmath.o: fastmath.cpp
	g++ -c fastmath.cpp

# BUG: missing libfastmath.a in the compilation line
poly_eval: poly_eval.cpp libfastmath.a
	g++ -o poly_eval poly_eval.cpp -I.
EOF

    cat << 'EOF' > /home/user/poly_service/input.txt
DEG: 2 | COEFFS: 1.0,2.0,3.0 | X: 2.0
DEG: 3 | COEFFS: 0.5,0.0,1.5,2.0| X: 1.0
DEG: 1 | COEFFS: -1.0,5.0| X: 3.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
