#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential cmake

pip3 install pytest nbformat papermill jupyter pandas

mkdir -p /home/user/sim
cd /home/user/sim

# 1. Create CMakeLists.txt
cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(VanDerPolSim)
set(CMAKE_CXX_STANDARD 11)
add_executable(vdp_sim integrator.cpp)
EOF

# 2. Create integrator.cpp
cat << 'EOF' > integrator.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <algorithm>

const double MU = 1.0;
const double TOL = 1e-5;

void f(double t, const std::vector<double>& y, std::vector<double>& dydt) {
    dydt[0] = y[1];
    dydt[1] = MU * (1.0 - y[0] * y[0]) * y[1] - y[0];
}

int main(int argc, char** argv) {
    double t = 0.0;
    double t_end = 20.0;
    double dt = 0.1;

    std::vector<double> y = {2.0, 0.0};
    std::vector<double> k1(2), k2(2), y_temp(2), y_err(2), y_next(2);

    std::ofstream out("output.csv");
    out << "t,x,v\n";
    out << t << "," << y[0] << "," << y[1] << "\n";

    int steps = 0;
    while (t < t_end && steps < 10000) {
        f(t, y, k1);
        for(int i=0; i<2; ++i) y_temp[i] = y[i] + dt * k1[i];

        f(t + dt, y_temp, k2);

        double error = 0.0;
        for(int i=0; i<2; ++i) {
            y_next[i] = y[i] + dt * (k1[i] + k2[i]) / 2.0;
            y_err[i]  = y[i] + dt * k1[i];
            error = std::max(error, std::abs(y_next[i] - y_err[i]));
        }

        error = std::max(error, 1e-15); // Avoid division by zero

        // BUG: error / TOL instead of TOL / error
        double scale = 0.9 * std::sqrt(error / TOL); 

        if (error <= TOL) {
            t += dt;
            y = y_next;
            out << t << "," << y[0] << "," << y[1] << "\n";
            // Check for divergence
            if (std::abs(y[0]) > 1e4 || std::isnan(y[0])) {
                break;
            }
        }

        dt = dt * std::max(0.1, std::min(5.0, scale));
        steps++;
    }
    out.close();
    return 0;
}
EOF

# 3. Create a python script to generate the jupyter notebook
cat << 'EOF' > generate_nb.py
import nbformat as nbf

nb = nbf.v4.new_notebook()

code1 = """\
import subprocess
import pandas as pd
import json
import os

# Run the simulation
print("Running simulation...")
res = subprocess.run(["./build/vdp_sim"], capture_output=True, text=True)
if res.returncode != 0:
    print("Simulation failed!")
else:
    print("Simulation finished.")
"""

code2 = """\
# Read the output
if not os.path.exists("output.csv"):
    result = {"status": "failed", "reason": "No output.csv generated"}
else:
    df = pd.read_csv("output.csv")
    max_val = df['x'].abs().max()
    if max_val > 1000 or pd.isna(max_val):
        result = {"status": "diverged", "max_x": float(max_val)}
    else:
        result = {"status": "stable", "max_x": float(max_val), "steps": len(df)}

with open("result.json", "w") as f:
    json.dump(result, f)

print(f"Result: {result}")
"""

nb['cells'] = [nbf.v4.new_code_cell(code1), nbf.v4.new_code_cell(code2)]
with open('experiment.ipynb', 'w') as f:
    nbf.write(nb, f)
EOF

python3 generate_nb.py
rm generate_nb.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
