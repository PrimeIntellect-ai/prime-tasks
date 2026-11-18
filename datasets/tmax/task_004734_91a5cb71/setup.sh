#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        build-essential \
        cmake \
        libfmt-dev \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'Target SLA: 99.999%'" /app/alert_dashboard.png

    mkdir -p /home/user/uptime_monitor/src
    mkdir -p /home/user/uptime_monitor/data

    cat << 'EOF' > /home/user/uptime_monitor/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(uptime_monitor)

set(CMAKE_CXX_STANDARD 17)

# Dependency conflict: requiring exact version 7.0.0 which doesn't match system libfmt
find_package(fmt 7.0.0 EXACT REQUIRED)

add_executable(uptime_monitor src/uptime_calculator.cpp)
target_link_libraries(uptime_monitor fmt::fmt)
EOF

    cat << 'EOF' > /home/user/uptime_monitor/src/uptime_calculator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <iomanip>
#include <fmt/core.h>

struct Ping {
    float duration_ms;
};

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <csv_file>\n";
        return 1;
    }
    std::ifstream file(argv[1]);
    std::string line;
    std::vector<Ping> pings;
    while (std::getline(file, line)) {
        if (line.empty() || line == "duration_ms") continue;
        pings.push_back({std::stof(line)});
    }

    float total_uptime_ms = 0.0f;
    for(auto ping : pings) {
        total_uptime_ms += ping.duration_ms;
    }

    // Expected total time is 10,000,000.0 ms
    double expected_total = 10000000.0;
    double sla = (total_uptime_ms / expected_total) * 100.0;

    std::cout << std::fixed << std::setprecision(6) << sla << std::endl;
    return 0;
}
EOF

    python3 -c '
import os
target = 9999914.2
n = 1000000
base = target / n
with open("/home/user/uptime_monitor/data/ping_logs.csv", "w") as f:
    f.write("duration_ms\n")
    for _ in range(n):
        f.write(f"{base:.7f}\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
