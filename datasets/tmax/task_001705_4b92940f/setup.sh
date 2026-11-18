#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        git \
        g++ \
        nlohmann-json3-dev \
        && rm -rf /var/lib/apt/lists/*

    pip3 install pytest

    mkdir -p /app/data/clean
    mkdir -p /app/data/evil
    mkdir -p /home/user/legacy_wrapper

    # Create Git repository
    cd /home/user/legacy_wrapper
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo 'TOKEN = "HFT_AUTH_9921_XY"' > wrapper.py
    git add wrapper.py
    git commit -m "Initial wrapper script"

    echo 'TOKEN = "REDACTED"' > wrapper.py
    git add wrapper.py
    git commit -m "Remove sensitive token"

    echo '# Legacy Wrapper' > README.md
    git add README.md
    git commit -m "Add readme"

    # Create C++ engine
    cat << 'EOF' > /app/engine.cpp
#include <iostream>
#include <fstream>
#include <cmath>
#include <string>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <TOKEN> <input.json>\n";
        return 2;
    }
    std::string token = argv[1];
    if (token != "HFT_AUTH_9921_XY") {
        std::cerr << "Unauthorized\n";
        return 2;
    }
    std::ifstream ifs(argv[2]);
    if (!ifs.is_open()) return 1;
    json j;
    ifs >> j;

    double alpha = j["alpha"];
    double beta = j["beta"];
    double gamma = j["gamma"];

    if (std::abs(std::exp(alpha) - beta) < 1e-5) {
        volatile int x = 0;
        int y = 1 / x; // crash
        std::cout << y;
    }
    if (gamma < 0.0) {
        std::cerr << "ERR_NEGATIVE_GAMMA_PANIC\n";
        volatile int* p = nullptr;
        *p = 42; // crash
    }
    std::cout << "Success\n";
    return 0;
}
EOF

    g++ -O2 -o /app/engine /app/engine.cpp
    strip /app/engine
    rm /app/engine.cpp

    # Generate data
    cat << 'EOF' > /app/generate_data.py
import os
import json
import math

# Clean: abs(exp(alpha) - beta) > 0.1 and gamma >= 0.0
for i in range(50):
    alpha = i * 0.1
    beta = math.exp(alpha) + 0.5
    gamma = i * 0.5 + 0.1
    with open(f'/app/data/clean/data_{i}.json', 'w') as f:
        json.dump({"alpha": alpha, "beta": beta, "gamma": gamma}, f)

# Evil 1: abs(exp(alpha) - beta) < 1e-5
for i in range(25):
    alpha = i * 0.1
    beta = math.exp(alpha)
    gamma = i * 0.5 + 0.1
    with open(f'/app/data/evil/data_cond1_{i}.json', 'w') as f:
        json.dump({"alpha": alpha, "beta": beta, "gamma": gamma}, f)

# Evil 2: gamma < 0.0
for i in range(25):
    alpha = i * 0.1
    beta = math.exp(alpha) + 0.5
    gamma = -1.0 - i * 0.1
    with open(f'/app/data/evil/data_cond2_{i}.json', 'w') as f:
        json.dump({"alpha": alpha, "beta": beta, "gamma": gamma}, f)
EOF

    python3 /app/generate_data.py
    rm /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
