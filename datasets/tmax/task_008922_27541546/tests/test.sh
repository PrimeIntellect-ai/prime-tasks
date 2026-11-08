#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_results_exist():
    assert os.path.isfile('/home/user/results.txt'), "/home/user/results.txt does not exist."

def test_results_content():
    # We write and compile the reference C++ implementation to get the exact expected output,
    # because C++'s std::mt19937 and floating point operations need to be matched exactly.
    cpp_code = """
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <random>
#include <algorithm>
#include <iomanip>

int main() {
    std::ifstream file("/home/user/data.csv");
    std::string line;
    if (!std::getline(file, line)) return 1; // skip header
    std::vector<double> sq_errors;
    while (std::getline(file, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string val;
        double spend, visits, actual;
        std::getline(ss, val, ','); spend = std::stod(val);
        std::getline(ss, val, ','); visits = std::stod(val);
        std::getline(ss, val, ','); actual = std::stod(val);
        double pred = 2.5 * spend + 1.2 * visits + 10.0;
        double se = (actual - pred) * (actual - pred);
        sq_errors.push_back(se);
    }

    int N = sq_errors.size();
    if (N == 0) return 1;

    double orig_mse = 0;
    for (double se : sq_errors) orig_mse += se;
    orig_mse /= N;

    std::mt19937 gen(42);
    std::uniform_int_distribution<int> dist(0, N - 1);

    std::vector<double> boot_mses(1000);
    double boot_mean = 0;
    for (int i = 0; i < 1000; ++i) {
        double sum = 0;
        for (int j = 0; j < N; ++j) {
            sum += sq_errors[dist(gen)];
        }
        boot_mses[i] = sum / N;
        boot_mean += boot_mses[i];
    }
    boot_mean /= 1000.0;

    std::sort(boot_mses.begin(), boot_mses.end());

    std::ofstream out("/home/user/truth_results.txt");
    out << std::fixed << std::setprecision(4);
    out << "Original MSE: " << orig_mse << "\\n";
    out << "Bootstrap Mean MSE: " << boot_mean << "\\n";
    out << "95% CI Lower: " << boot_mses[25] << "\\n";
    out << "95% CI Upper: " << boot_mses[975] << "\\n";
    return 0;
}
"""
    truth_cpp_path = '/tmp/truth.cpp'
    truth_bin_path = '/tmp/truth'
    truth_out_path = '/home/user/truth_results.txt'

    with open(truth_cpp_path, 'w') as f:
        f.write(cpp_code)

    try:
        subprocess.run(['g++', '-O3', truth_cpp_path, '-o', truth_bin_path], check=True, capture_output=True)
        subprocess.run([truth_bin_path], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compile or run ground truth C++ code: {e.stderr.decode()}")

    assert os.path.isfile(truth_out_path), "Ground truth results file was not generated."

    with open(truth_out_path, 'r') as f:
        truth_content = f.read().strip()

    with open('/home/user/results.txt', 'r') as f:
        student_content = f.read().strip()

    assert student_content == truth_content, (
        f"The contents of /home/user/results.txt do not match the expected output.\n"
        f"Expected:\n{truth_content}\n\nGot:\n{student_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
