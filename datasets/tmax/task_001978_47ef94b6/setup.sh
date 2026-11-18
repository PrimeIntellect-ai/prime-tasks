#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cmake build-essential
    pip3 install --default-timeout=100 pytest pandas numpy

    mkdir -p /app
    mkdir -p /home/user/math_engine_repo/src

    cd /home/user/math_engine_repo

    cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(math_engine)
set(CMAKE_CXX_STANDARD 14)
add_executable(engine src/main.cpp src/parser.cpp src/integrator.cpp)
EOF

    cat << 'EOF' > src/integrator.h
#pragma once
double integrate(double lower, double upper, int steps);
EOF

    cat << 'EOF' > src/integrator.cpp
#include "integrator.h"
double f(double x) {
    return 3 * x * x + 2 * x;
}
double integrate(double lower, double upper, int steps) {
    if (steps <= 0) return 0;
    double h = (upper - lower) / steps;
    double sum = 0.5 * (f(lower) + f(upper));
    for (int i = 1; i < steps; ++i) {
        sum += f(lower + i * h);
    }
    return sum * h;
}
EOF

    cat << 'EOF' > src/parser.h
#pragma once
#include <string>
#include <vector>
struct Query {
    std::string id;
    double lower;
    double upper;
    int steps;
};
std::vector<Query> parse_queries(const std::string& filename);
EOF

    cat << 'EOF' > src/parser.cpp
#include "parser.h"
#include <fstream>
#include <sstream>
#include <iostream>

std::vector<Query> parse_queries(const std::string& filename) {
    std::vector<Query> queries;
    std::ifstream infile(filename);
    std::string line;
    while (std::getline(infile, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string id_str, lower_str, upper_str, steps_str;
        if (std::getline(ss, id_str, ',') &&
            std::getline(ss, lower_str, ',') &&
            std::getline(ss, upper_str, ',') &&
            std::getline(ss, steps_str, ',')) {
            Query q;
            q.id = id_str;
            q.lower = std::stod(lower_str);
            q.upper = std::stod(upper_str);
            q.steps = std::stoi(steps_str);
            queries.push_back(q);
        }
    }
    return queries;
}
EOF

    cat << 'EOF' > src/main.cpp
#include "parser.h"
#include "integrator.h"
#include <iostream>
#include <fstream>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <input.csv> <output.csv>\n";
        return 1;
    }
    auto queries = parse_queries(argv[1]);
    std::ofstream outfile(argv[2]);
    outfile << std::fixed << std::setprecision(6);
    for (const auto& q : queries) {
        double res = integrate(q.lower, q.upper, q.steps);
        outfile << q.id << "," << res << "\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > test_queries.csv
q1,0.0,1.0,100
q2,1.0,5.0,200
q3,-2.0,2.0,500
q4,0.0,10.0,1000
EOF

    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    git init
    git add .
    git commit -m "Initial commit"

    # Compile the oracle engine
    mkdir build_oracle
    cd build_oracle
    cmake ..
    make
    strip engine
    cp engine /app/oracle_engine
    cd ..
    rm -rf build_oracle

    # Create 200 commits. Introduce bug at commit 127.
    for i in $(seq 1 200); do
        if [ $i -eq 127 ]; then
            sed -i 's/q.steps = std::stoi(steps_str);/q.steps = std::stoi(steps_str) - 1;/' src/parser.cpp
        fi
        echo "// Commmit $i" >> src/main.cpp
        git add src/main.cpp src/parser.cpp
        git commit -m "Commit $i"
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
