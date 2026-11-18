#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/metrics_tool

    cat << 'EOF' > /home/user/metrics_tool/main.cpp
#include <iostream>
#include <string>
#include <sstream>
#include <iomanip>
#include "calculator.h"

bool check_rate_limit(int timestamp);

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string ts_str, val_str;
        if (std::getline(ss, ts_str, ',') && std::getline(ss, val_str)) {
            int ts = std::stoi(ts_str);
            double val = std::stod(val_str);

            if (!check_rate_limit(ts)) {
                std::cout << ts << ",RATE_LIMIT_EXCEEDED" << std::endl;
            } else {
                double sma = compute_sma(val);
                std::cout << ts << "," << std::fixed << std::setprecision(2) << sma << std::endl;
            }
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/metrics_tool/rate_limiter.cpp
#include <map>

// Simple rate limiter: max 2 requests per second
std::map<int, int> request_counts;

bool check_rate_limit(int timestamp) {
    if (request_counts[timestamp] >= 2) {
        return false;
    }
    request_counts[timestamp]++;
    return true;
}
EOF

    cat << 'EOF' > /home/user/metrics_tool/calculator.h
#ifndef CALCULATOR_H
#define CALCULATOR_H

double compute_sma(double new_value);

#endif
EOF

    cat << 'EOF' > /home/user/metrics_tool/calculator.cpp
#include "calculator.h"
#include <vector>

// TODO: Implement simple moving average (window size 3)
double compute_sma(double new_value) {
    return 0.0;
}
EOF

    cat << 'EOF' > /home/user/metrics_tool/Makefile
# Broken Makefile
CC=g++
CFLAGS=-I.

metrics_tool: main.o calculator.o
	$(CC) -o metrics_tool main.o calculator.o

main.o: main.cpp
	$(CC) -c main.cpp

calculator.o: calculator.cpp
	$(CC) -c calculator.cpp

# Missing rate_limiter.o in compilation and linking
EOF

    chmod -R 777 /home/user
