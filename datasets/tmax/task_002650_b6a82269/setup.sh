#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget g++ make
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /workspace

    # Download and extract nlohmann/json v3.11.2
    cd /app
    wget https://github.com/nlohmann/json/archive/refs/tags/v3.11.2.tar.gz
    tar -xzf v3.11.2.tar.gz
    mv json-3.11.2 json
    rm v3.11.2.tar.gz

    # Apply perturbations to lexer.hpp
    LEXER_FILE="/app/json/include/nlohmann/detail/input/lexer.hpp"

    # Perturbation 1: Build Failure (comment out cmath and cstdlib)
    sed -i 's/#include <cmath>/\/\/ #include <cmath>/g' $LEXER_FILE
    sed -i 's/#include <cstdlib>/\/\/ #include <cstdlib>/g' $LEXER_FILE

    # Perturbation 2: Infinite loop in skip_whitespace
    sed -i 's/get();/\/\/ get();/g' $LEXER_FILE

    # Perturbation 3: Precision loss in scan_number
    # Replace std::strtod with static_cast<float>(std::strtod(...))
    sed -i 's/std::strtod(number_buffer.data(), &endptr)/static_cast<float>(std::strtod(number_buffer.data(), \&endptr))/g' $LEXER_FILE

    # Generate logs.json
    cat << 'EOF' > /workspace/generate_logs.py
import json
import random

random.seed(42)
logs = []
for _ in range(10000):
    # Generate high precision floats
    latency = random.uniform(0.000000001, 0.000000010)
    logs.append({"latency": latency})

with open("/workspace/logs.json", "w") as f:
    json.dump(logs, f)
EOF
    python3 /workspace/generate_logs.py
    rm /workspace/generate_logs.py

    # Create process_metrics.cpp
    cat << 'EOF' > /workspace/process_metrics.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <iomanip>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main() {
    std::ifstream f("/workspace/logs.json");
    if (!f.is_open()) {
        std::cerr << "Failed to open logs.json" << std::endl;
        return 1;
    }

    json data;
    f >> data;

    std::vector<double> latencies;
    for (const auto& item : data) {
        latencies.push_back(item["latency"].get<double>());
    }

    if (latencies.empty()) return 0;

    double sum = 0.0;
    for (double l : latencies) sum += l;
    double mean = sum / latencies.size();

    double sq_sum = 0.0;
    for (double l : latencies) {
        sq_sum += (l - mean) * (l - mean);
    }
    double stddev = std::sqrt(sq_sum / latencies.size());

    std::ofstream out("/workspace/output.txt");
    out << std::setprecision(17) << stddev << std::endl;

    return 0;
}
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /workspace /app
    chmod -R 777 /home/user /workspace /app
