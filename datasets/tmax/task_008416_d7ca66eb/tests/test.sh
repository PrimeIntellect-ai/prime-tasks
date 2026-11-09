#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

SOURCE = "/home/user/bootstrap.cpp"
DATA = "/home/user/data.csv"
RESULT = "/home/user/bootstrap_results.txt"
BINARY = "/tmp/submitted_bootstrap"
ORACLE_SOURCE = "/tmp/bootstrap_oracle.cpp"
ORACLE_BINARY = "/tmp/bootstrap_oracle"

ORACLE_CODE = r'''
#include <algorithm>
#include <cerrno>
#include <charconv>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <string>
#include <vector>

static bool parse_int(const std::string& s, int& value) {
    if (s.empty()) return false;
    const char* first = s.data();
    const char* last = first + s.size();
    auto result = std::from_chars(first, last, value);
    return result.ec == std::errc() && result.ptr == last;
}

static bool parse_double(const std::string& s, double& value) {
    if (s.empty()) return false;
    char* end = nullptr;
    errno = 0;
    value = std::strtod(s.c_str(), &end);
    return errno == 0 && end == s.c_str() + s.size() && std::isfinite(value);
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::ifstream input(argv[1]);
    if (!input) return 3;

    std::vector<double> scores;
    std::string line;
    while (std::getline(input, line)) {
        size_t first = line.find(',');
        if (first == std::string::npos) continue;
        size_t second = line.find(',', first + 1);
        if (second == std::string::npos || line.find(',', second + 1) != std::string::npos) continue;

        std::string id_text = line.substr(0, first);
        std::string age_text = line.substr(first + 1, second - first - 1);
        std::string score_text = line.substr(second + 1);
        int id, age;
        double score;
        if (!parse_int(id_text, id) || !parse_int(age_text, age) ||
            !parse_double(score_text, score)) continue;
        scores.push_back(score);
    }

    const size_t n = scores.size();
    if (n == 0) return 4;
    std::mt19937 rng(42);
    std::uniform_int_distribution<size_t> distribution(0, n - 1);
    std::vector<double> means;
    means.reserve(10000);
    double total_means = 0.0;

    for (int iteration = 0; iteration < 10000; ++iteration) {
        double sum = 0.0;
        for (size_t i = 0; i < n; ++i) sum += scores[distribution(rng)];
        double mean = sum / static_cast<double>(n);
        means.push_back(mean);
        total_means += mean;
    }

    std::sort(means.begin(), means.end());
    std::cout << std::fixed << std::setprecision(2)
              << "Valid rows: " << n << "\n"
              << "Mean: " << total_means / 10000.0 << "\n"
              << "95% CI: [" << means[250] << ", " << means[9749] << "]\n";
    return 0;
}
'''


def run_submission():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert completed.returncode == 0, (
        "Compiled bootstrap program failed: " + completed.stderr.decode(errors="replace")
    )
    assert os.path.isfile(RESULT), "The compiled program did not generate bootstrap_results.txt"


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(SOURCE), f"Error: {SOURCE} does not exist. Make sure you saved your C++ code to this location."
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O3", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        "bootstrap.cpp did not compile: " + compile_result.stderr.decode(errors="replace")
    )

    with open(ORACLE_SOURCE, "w") as f:
        f.write(ORACLE_CODE)
    oracle_compile = subprocess.run(
        ["g++", "-std=c++17", "-O3", ORACLE_SOURCE, "-o", ORACLE_BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert oracle_compile.returncode == 0, oracle_compile.stderr.decode(errors="replace")

    with open(DATA, "rb") as f:
        original_data = f.read()
    run_submission()
    yield
    with open(DATA, "wb") as f:
        f.write(original_data)
    run_submission()


def test_bootstrap_results_exists():
    file_path = "/home/user/bootstrap_results.txt"
    assert os.path.isfile(file_path), f"Error: {file_path} does not exist. Did you run your C++ program and generate the output?"


def test_bootstrap_results_content():
    file_path = "/home/user/bootstrap_results.txt"
    with open(file_path, "r") as f:
        content = f.read()

    # Check Valid rows
    assert "Valid rows: 11" in content, "Error: The number of valid rows is incorrect. Expected 'Valid rows: 11'."

    # Check Mean (should start with 86.6, as 86.64 is the exact expected value but we allow some flexibility)
    assert re.search(r"Mean:\s*86\.6", content), "Error: The overall mean is incorrect. Expected a value around 86.6X."

    # Check 95% CI format
    assert "95% CI:" in content, "Error: '95% CI:' not found in the output."
    assert re.search(r"95% CI:\s*\[\d+\.\d{2},\s*\d+\.\d{2}\]", content), "Error: The 95% CI format is incorrect. Expected '95% CI: [L.LL, U.UU]'."


def test_cpp_source_exists():
    file_path = "/home/user/bootstrap.cpp"
    assert os.path.isfile(file_path), f"Error: {file_path} does not exist. Make sure you saved your C++ code to this location."


def test_program_on_additional_datasets():
    with open(DATA, "rb") as f:
        original_data = f.read()

    random_scores = [20 + secrets.randbelow(800) for _ in range(13)]
    datasets = [
        (
            "1,20,10\n"
            "2,21,20\n"
            "3,,30\n"
            "4,22,40\n"
            "bad,23,50\n"
            "6,24,60,extra\n"
            "7,25,70\n"
            "8,26,not-a-number\n"
            "9,27,90\n"
            "10,28,100\n"
        ),
        "".join(f"{i + 1},{18 + (i % 50)},{score}\n" for i, score in enumerate(random_scores))
        + "100,,55\n101,33,44,extra\n102,age,75\n103,30,\n"
    ]

    try:
        for dataset in datasets:
            with open(DATA, "w") as f:
                f.write(dataset)
            expected_run = subprocess.run(
                [ORACLE_BINARY, DATA], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=20
            )
            assert expected_run.returncode == 0, "Internal oracle failed"
            run_submission()
            with open(RESULT, "rb") as f:
                actual = f.read()
            assert actual == expected_run.stdout, (
                "Program output did not match the required strict parsing and "
                "10,000-iteration seeded bootstrap calculation.\n"
                f"Expected:\n{expected_run.stdout.decode(errors='replace')}"
                f"Actual:\n{actual.decode(errors='replace')}"
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        run_submission()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
