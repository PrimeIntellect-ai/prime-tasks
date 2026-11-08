#!/bin/bash
mkdir -p /logs/verifier

cat << 'ORACLE_EOF' > /tmp/ci_oracle.cpp
#include <algorithm>
#include <charconv>
#include <cctype>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

static bool strict_integer(const std::string& value) {
    if (value.empty()) return false;
    long long parsed = 0;
    const char* begin = value.data();
    const char* end = begin + value.size();
    auto result = std::from_chars(begin, end, parsed);
    return result.ec == std::errc() && result.ptr == end;
}

static std::vector<std::string> read_vocab(const std::string& path) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("cannot read vocabulary");
    std::vector<std::string> vocab;
    std::string line;
    while (std::getline(input, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        vocab.push_back(line);
    }
    return vocab;
}

static std::vector<double> read_first_projection_column(const std::string& path,
                                                         std::size_t expected_rows) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("cannot read projection");
    std::vector<double> first_column;
    std::string line;
    while (std::getline(input, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        std::stringstream row(line);
        std::string first, second, extra;
        if (!std::getline(row, first, ',') || !std::getline(row, second, ',') ||
            std::getline(row, extra, ',')) {
            throw std::runtime_error("invalid projection row");
        }
        std::size_t p1 = 0, p2 = 0;
        double a = std::stod(first, &p1);
        (void)std::stod(second, &p2);
        if (p1 != first.size() || p2 != second.size())
            throw std::runtime_error("invalid projection value");
        first_column.push_back(a);
    }
    if (first_column.size() != expected_rows)
        throw std::runtime_error("projection row count mismatch");
    return first_column;
}

int main(int argc, char** argv) {
    if (argc != 4) return 2;
    try {
        const auto vocab = read_vocab(argv[2]);
        const auto projection = read_first_projection_column(argv[3], vocab.size());
        std::unordered_map<std::string, std::size_t> positions;
        for (std::size_t i = 0; i < vocab.size(); ++i) positions[vocab[i]] = i;

        std::ifstream logs(argv[1]);
        if (!logs) throw std::runtime_error("cannot read logs");
        std::string line;
        std::getline(logs, line); // header
        std::vector<double> projected;
        while (std::getline(logs, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            const std::size_t first_comma = line.find(',');
            const std::size_t second_comma = first_comma == std::string::npos
                ? std::string::npos : line.find(',', first_comma + 1);
            if (first_comma == std::string::npos || second_comma == std::string::npos)
                continue;
            const std::string id = line.substr(0, first_comma);
            if (!strict_integer(id)) continue;

            std::string message = line.substr(second_comma + 1);
            for (char& ch : message)
                ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));

            std::vector<long long> counts(vocab.size(), 0);
            std::stringstream words(message);
            std::string token;
            while (std::getline(words, token, ' ')) {
                auto it = positions.find(token);
                if (it != positions.end()) ++counts[it->second];
            }

            double value = 0.0;
            for (std::size_t i = 0; i < counts.size(); ++i)
                value += static_cast<double>(counts[i]) * projection[i];
            projected.push_back(value);
        }

        if (projected.empty()) throw std::runtime_error("no valid rows");
        const int n = static_cast<int>(projected.size());
        std::mt19937 gen(42);
        std::uniform_int_distribution<> dis(0, n - 1);
        std::vector<double> means;
        means.reserve(10000);
        for (int iteration = 0; iteration < 10000; ++iteration) {
            double sum = 0.0;
            for (int sample = 0; sample < n; ++sample) sum += projected[dis(gen)];
            means.push_back(sum / n);
        }
        std::sort(means.begin(), means.end());
        std::cout << std::fixed << std::setprecision(4)
                  << "Lower: " << means[250] << ", Upper: " << means[9750] << "\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    return 0;
}
ORACLE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

DATA = Path('/home/user/data')
OUTPUT = Path('/home/user/output/ci.txt')
ORACLE = '/tmp/ci_oracle'


def test_eigen_installed():
    header_path = "/home/user/eigen/Eigen/Dense"
    assert os.path.exists(header_path), f"Eigen headers not found at {header_path}"


def test_cpp_code_exists():
    cpp_path = "/home/user/process_logs.cpp"
    assert os.path.exists(cpp_path), f"C++ source code not found at {cpp_path}"


def test_binary_exists():
    bin_path = "/home/user/process_logs"
    assert os.path.exists(bin_path), f"Compiled binary not found at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"File at {bin_path} is not executable"


def test_output_file_exists_and_correct():
    out_path = "/home/user/output/ci.txt"
    assert os.path.exists(out_path), f"Output file not found at {out_path}"

    with open(out_path, "r") as f:
        content = f.read().strip()

    match = re.search(r"Lower:\s*([\d.]+),\s*Upper:\s*([\d.]+)", content)
    assert match is not None, (
        "Output format incorrect. Expected 'Lower: <value>, Upper: <value>', "
        f"got: {content}"
    )
    lower = float(match.group(1))
    upper = float(match.group(2))
    assert 0.4 <= lower <= 0.7, f"Lower bound {lower} is outside expected range [0.4, 0.7]"
    assert 1.1 <= upper <= 1.5, f"Upper bound {upper} is outside expected range [1.1, 1.5]"


def oracle_result():
    result = subprocess.run(
        [ORACLE, str(DATA / 'logs.csv'), str(DATA / 'vocab.txt'),
         str(DATA / 'projection.csv')],
        check=True, capture_output=True, text=True, timeout=10,
    )
    return result.stdout.strip()


def run_and_check(executable, expected):
    if OUTPUT.exists():
        OUTPUT.unlink()
    subprocess.run([executable], cwd='/home/user', check=True, timeout=20)
    assert OUTPUT.exists(), f"{executable} did not create {OUTPUT}"
    actual = OUTPUT.read_text().strip()
    assert re.fullmatch(r"Lower: -?\d+\.\d{4}, Upper: -?\d+\.\d{4}", actual), (
        f"Output must use exactly four decimal places, got: {actual}"
    )
    assert actual == expected, f"Expected {expected!r}, got {actual!r}"


def test_program_executes_and_recomputes_ci():
    paths = [DATA / 'logs.csv', DATA / 'vocab.txt', DATA / 'projection.csv']
    saved_data = {path: path.read_bytes() for path in paths}
    saved_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    fixtures = [
        saved_data,
        {
            DATA / 'logs.csv': (
                b'id,timestamp,message\n'
                b'10,11:00,ALPHA beta alpha\n'
                b'7x,11:01,alpha alpha alpha\n'
                b'-2,11:02,Gamma beta\n'
                b'003,11:03,beta  alpha\n'
                b'bad,11:04,delta delta delta\n'
            ),
            DATA / 'vocab.txt': b'alpha\nbeta\ngamma\ndelta\n',
            DATA / 'projection.csv': b'0.4,9.0\n-0.3,8.0\n1.2,7.0\n2.0,6.0\n',
        },
    ]

    verified_binary = '/tmp/process_logs_verified'
    subprocess.run([
        'g++', '-O3', '-I/home/user/eigen/', '/home/user/process_logs.cpp',
        '-o', verified_binary
    ], check=True, timeout=60)

    try:
        for fixture in fixtures:
            for executable in ('/home/user/process_logs', verified_binary):
                for path, content in fixture.items():
                    path.write_bytes(content)
                expected = oracle_result()
                run_and_check(executable, expected)
    finally:
        for path, content in saved_data.items():
            path.write_bytes(content)
        if saved_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_bytes(saved_output)
TEST_EOF

if g++ -O2 -std=c++17 /tmp/ci_oracle.cpp -o /tmp/ci_oracle \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
