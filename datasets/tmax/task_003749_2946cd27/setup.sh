#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake
    pip3 install pytest

    mkdir -p /home/user/pipeline/src
    mkdir -p /home/user/pipeline/build
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensor_data.csv
feature1,feature2
10.5,20.1
11.2,21.0
10.8,20.5
12.1,22.3
11.5,21.8
12.8,23.1
13.0,23.5
12.5,22.9
14.2,25.0
13.8,24.5
EOF

    cat << 'EOF' > /home/user/pipeline/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(ETLPipeline)
set(CMAKE_CXX_STANDARD 17)
add_executable(etl_pipeline src/main.cpp src/processor.cpp)
EOF

    cat << 'EOF' > /home/user/pipeline/src/processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H
#include <vector>

std::vector<double> compute_zscore(const std::vector<double>& data);
double compute_pearson_correlation(const std::vector<double>& x, const std::vector<double>& y);

#endif
EOF

    cat << 'EOF' > /home/user/pipeline/src/processor.cpp
#include "processor.h"
#include <cmath>
#include <numeric>

// BUGGY: Uses future data (global mean/std)
std::vector<double> compute_zscore(const std::vector<double>& data) {
    std::vector<double> result(data.size(), 0.0);
    if (data.empty()) return result;

    double sum = std::accumulate(data.begin(), data.end(), 0.0);
    double mean = sum / data.size();

    double variance_sum = 0.0;
    for (double val : data) {
        variance_sum += (val - mean) * (val - mean);
    }
    double std_dev = std::sqrt(variance_sum / (data.size() - 1));

    for (size_t i = 0; i < data.size(); ++i) {
        if (std_dev == 0.0) result[i] = 0.0;
        else result[i] = (data[i] - mean) / std_dev;
    }
    return result;
}

double compute_pearson_correlation(const std::vector<double>& x, const std::vector<double>& y) {
    // TODO: Implement Pearson correlation
    return 0.0;
}
EOF

    cat << 'EOF' > /home/user/pipeline/src/main.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <iomanip>
#include "processor.h"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <csv_file>\n";
        return 1;
    }

    std::ifstream file(argv[1]);
    std::string line;
    std::vector<double> f1, f2;

    // Skip header
    std::getline(file, line);
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string val1, val2;
        std::getline(ss, val1, ',');
        std::getline(ss, val2, ',');
        f1.push_back(std::stod(val1));
        f2.push_back(std::stod(val2));
    }

    std::vector<double> f1_norm = compute_zscore(f1);
    double corr = compute_pearson_correlation(f1, f2);

    std::cout << "Pearson Correlation: " << std::fixed << std::setprecision(4) << corr << "\n";

    std::ofstream out("predictions.csv");
    out << "id,pred\n";
    for (size_t i = 0; i < f1_norm.size(); ++i) {
        // Simple mock inference model
        double pred = f1_norm[i] * 0.5 + 1.2;
        out << i << "," << std::fixed << std::setprecision(4) << pred << "\n";
    }
    out.close();

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
