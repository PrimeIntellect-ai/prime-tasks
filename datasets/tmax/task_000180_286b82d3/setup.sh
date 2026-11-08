#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest pandas numpy

    mkdir -p /home/user/workspace /app/minifft-1.2.0/include /app/minifft-1.2.0/src

    cat << 'EOF' > /app/minifft-1.2.0/include/minifft.h
#pragma once
#include <vector>
#include <complex>
namespace MiniFFT {
    void forward_transform(const std::vector<double>& input, std::vector<std::complex<double>>& output);
}
EOF

    cat << 'EOF' > /app/minifft-1.2.0/src/minifft.cpp
#include "minifft.h"
#include <cmath>
namespace MiniFFT {
    void forward_transform(const std::vector<double>& input, std::vector<std::complex<double>>& output) {
        size_t N = input.size();
        output.resize(N);
        for (size_t k = 0; k < N; ++k) {
            std::complex<double> sum(0.0, 0.0);
            for (size_t n = 0; n < N; ++n) {
                double angle = -2.0 * M_PI * k * n / N;
                sum += input[n] * std::complex<double>(cos(angle), sin(angle));
            }
            output[k] = sum;
        }
    }
}
EOF

    cat << 'EOF' > /app/minifft-1.2.0/Makefile
CXX = g++
CXXFLAGS = -O3 -Wall -march=native-invalid

libminifft.a: src/minifft.o
	ar rcs $@ $^

src/minifft.o: src/minifft.cpp
	$(CXX) $(CXXFLAGS) -I./include -c $< -o $@

clean:
	rm -f src/*.o libminifft.a
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/minifft-1.2.0
