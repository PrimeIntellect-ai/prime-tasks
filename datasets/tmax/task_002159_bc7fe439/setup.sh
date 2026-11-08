#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make
    pip3 install pytest

    mkdir -p /app/spectra_fitter-1.0/include
    mkdir -p /app/spectra_fitter-1.0/src

    cat << 'EOF' > /app/spectra_fitter-1.0/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(spectra_fitter)
add_library(spectra_fitter SHARED src/integrator.cpp src/fitter.cpp)
target_include_directories(spectra_fitter PUBLIC include)
install(TARGETS spectra_fitter DESTINATION lib)
install(FILES include/spectra_fitter.hpp DESTINATION include)
EOF

    cat << 'EOF' > /app/spectra_fitter-1.0/include/spectra_fitter.hpp
#pragma once
#include <vector>
class SpectraFitter {
public:
    static double fit_peak(const std::vector<double>& data);
};
EOF

    cat << 'EOF' > /app/spectra_fitter-1.0/src/fitter.cpp
#include "spectra_fitter.hpp"
extern double integrate_model(double init_val);
double SpectraFitter::fit_peak(const std::vector<double>& data) {
    double sum = 0;
    for(auto d : data) sum += d;
    return integrate_model(sum);
}
EOF

    cat << 'EOF' > /app/spectra_fitter-1.0/src/integrator.cpp
#include <cmath>
double integrate_model(double init_val) {
    double t = 0.0;
    double dt = 0.1;
    double val = init_val;
    while (t < 1.0) {
        double error = dt * 0.5; // mocked error calculation
        if (error > 0.02) {
            // PERTURBATION: Wrong adaptation. Should be dt /= 2.0;
            dt *= 2.0; 
            continue;
        }
        val += dt * std::sin(val);
        t += dt;
    }
    return val;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
