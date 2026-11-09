#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile

def test_best_primer_output():
    user_output_file = "/home/user/best_primer.txt"
    assert os.path.isfile(user_output_file), f"Expected output file {user_output_file} does not exist."

    # Create the ground truth C++ file to compute the exact expected output
    truth_cpp = """
#include <iostream>
#include <string>
#include <vector>
#include <random>
#include <fstream>

const std::string TARGET = "GCTAGCTAGCTAGCTAGCTA"; 
std::mt19937 gen(42);

double score_primer(const std::string& primer) {
    if (primer.length() != 10) return 0.0;
    double total_score = 0.0;
    std::uniform_real_distribution<> dis(0.0, 1.0);

    for (int mc = 0; mc < 100; ++mc) {
        std::string noisy_target = TARGET;
        for (char& c : noisy_target) {
            if (dis(gen) < 0.1) {
                const char bases[] = {'A', 'C', 'G', 'T'};
                c = bases[gen() % 4];
            }
        }

        int best_match = 0;
        for (size_t i = 0; i <= noisy_target.length() - 10; ++i) {
            int matches = 0;
            for (size_t j = 0; j < 10; ++j) {
                if (primer[j] == noisy_target[i+j]) matches++;
            }
            if (matches > best_match) best_match = matches;
        }
        total_score += best_match;
    }
    return total_score / 100.0;
}

std::string find_best_primer() {
    std::string current_primer = "AAAAAAAAAA";
    double current_score = score_primer(current_primer);
    std::mt19937 local_gen(123);
    const char bases[] = {'A', 'C', 'G', 'T'};

    for (int i = 0; i < 500; ++i) {
        std::string mutated = current_primer;
        int idx = local_gen() % 10;
        int base_idx = local_gen() % 4;
        mutated[idx] = bases[base_idx];

        double new_score = score_primer(mutated);
        if (new_score >= current_score) {
            current_primer = mutated;
            current_score = new_score;
        }
    }
    return current_primer;
}

int main() {
    std::string best = find_best_primer();
    double score = score_primer(best);
    std::ofstream out("expected_best_primer.txt");
    out << "Primer: " << best << "\\nScore: " << score << "\\n";
    return 0;
}
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        cpp_path = os.path.join(tmpdir, "truth.cpp")
        exe_path = os.path.join(tmpdir, "truth_exe")

        with open(cpp_path, "w") as f:
            f.write(truth_cpp)

        compile_proc = subprocess.run(["g++", "-O3", "-std=c++11", cpp_path, "-o", exe_path], capture_output=True)
        assert compile_proc.returncode == 0, "Failed to compile the truth C++ code."

        run_proc = subprocess.run([exe_path], cwd=tmpdir, capture_output=True)
        assert run_proc.returncode == 0, "Failed to run the truth C++ code."

        expected_output_file = os.path.join(tmpdir, "expected_best_primer.txt")
        with open(expected_output_file, "r") as f:
            expected_content = f.read().strip()

    with open(user_output_file, "r") as f:
        user_content = f.read().strip()

    assert user_content == expected_content, f"Content of {user_output_file} does not match expected output.\nExpected:\n{expected_content}\n\nGot:\n{user_content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
