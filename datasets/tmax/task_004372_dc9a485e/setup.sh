#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sim_backend.cpp
#include <iostream>
#include <string>
#include <iomanip>

double calculate_weights(double current, int depth) {
    // BUG: Missing base case for negative depth. 
    // When python passes a negative number, this recurses infinitely and causes a stack overflow.
    if (depth == 0) {
        return current;
    }
    return calculate_weights(current * 0.9, depth - 1);
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    int depth = std::stoi(argv[1]);

    // Calculate 
    double res = calculate_weights(100.0, depth);

    std::cout << std::fixed << std::setprecision(4) << res << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/controller.py
import subprocess
import json
import sys
import os

def run_sim():
    history = []

    # The simulation iteratively runs from depth 10 down to -4.
    # It expects the backend to safely handle negative depths (e.g., returning the base value).
    for i in range(10, -5, -1):
        try:
            res = subprocess.check_output(["/home/user/sim_backend", str(i)], stderr=subprocess.STDOUT)
            val = float(res.decode('utf-8').strip())
            history.append(val)
        except subprocess.CalledProcessError as e:
            print(f"Backend crashed at iteration {i}!")
            sys.exit(1)
        except ValueError:
            print("Invalid output from backend!")
            sys.exit(1)

    with open("/home/user/convergence_results.json", "w") as f:
        json.dump({"status": "converged", "history": history}, f)
    print("Simulation converged successfully.")

if __name__ == "__main__":
    if not os.path.exists("/home/user/sim_backend"):
        print("Backend executable not found!")
        sys.exit(1)
    run_sim()
EOF

    chmod +x /home/user/controller.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
