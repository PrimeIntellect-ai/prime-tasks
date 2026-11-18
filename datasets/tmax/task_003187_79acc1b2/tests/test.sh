#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

CPP_PATH = Path('/home/user/mlops_etl.cpp')
BIN_PATH = Path('/home/user/mlops_etl')
CSV_PATH = Path('/home/user/experiments.csv')
REPORT_PATH = Path('/home/user/report.txt')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=30, **kwargs)


def execute_submission():
    if REPORT_PATH.exists():
        REPORT_PATH.unlink()
    result = subprocess.run([str(BIN_PATH)], cwd='/home/user', timeout=30,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f'Program exited with status {result.returncode}: {result.stderr}'
    assert REPORT_PATH.is_file(), f'File {REPORT_PATH} is missing. Did the program run and generate the report?'
    return REPORT_PATH.read_text()


def check_original_assertions(content):
    assert 'Model: BetaNet' in content, "The report does not contain 'Model: BetaNet'."
    assert 'Valid Samples: 7' in content, "The report does not contain 'Valid Samples: 7'. Make sure data filtering is correct."

    mean_match = re.search(r'Mean of Means:\s*([0-9.]+)', content)
    assert mean_match is not None, "Could not find 'Mean of Means' in the report."
    mean_val = float(mean_match.group(1))
    assert abs(mean_val - 0.8542) <= 0.0002, f'Expected Mean of Means around 0.8542, but got {mean_val}.'

    ci_match = re.search(r'95% CI:\s*\[([0-9.]+),\s*([0-9.]+)\]', content)
    assert ci_match is not None, "Could not find '95% CI' bounds in the report."
    lower_bound = float(ci_match.group(1))
    upper_bound = float(ci_match.group(2))
    assert abs(lower_bound - 0.8343) <= 0.0002, f'Expected lower bound around 0.8343, but got {lower_bound}.'
    assert abs(upper_bound - 0.8743) <= 0.0002, f'Expected upper bound around 0.8743, but got {upper_bound}.'


def parse_strict_report(content):
    match = re.fullmatch(
        r'Model: BetaNet\n'
        r'Valid Samples: ([0-9]+)\n'
        r'Mean of Means: (-?[0-9]+\.[0-9]{4})\n'
        r'95% CI: \[(-?[0-9]+\.[0-9]{4}), (-?[0-9]+\.[0-9]{4})\]\n?',
        content
    )
    assert match is not None, 'Report does not have exactly the required four-line format with four decimal places.'
    return int(match.group(1)), float(match.group(2)), float(match.group(3)), float(match.group(4))


def oracle_values(accuracies):
    data = str(len(accuracies)) + '\n' + ' '.join(format(x, '.17g') for x in accuracies) + '\n'
    result = run(['/tmp/bootstrap_oracle'], input=data, text=True,
                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return tuple(float(x) for x in result.stdout.split())


def make_case(valid_count):
    rng = secrets.SystemRandom()
    rows = []
    for _ in range(valid_count):
        accuracy = rng.randrange(50000, 950001) / 1000000.0
        loss = rng.randrange(0, 800001) / 1000000.0
        rows.append(['BetaNet', f'{accuracy:.6f}', f'{loss:.6f}', accuracy])

    rows.extend([
        ['AlphaNet', f'{rng.randrange(1, 999999) / 1000000.0:.6f}', '0.200000', None],
        ['BetaNet', '', '0.300000', None],
        ['BetaNet', 'NaN', '0.300000', None],
        ['BetaNet', '0.750000', '', None],
        ['BetaNet', '0.750000', 'NaN', None],
        ['BetaNet', '1.000001', '0.100000', None],
        ['BetaNet', '-0.000001', '0.100000', None],
        ['BetaNet', '0.750000', '-0.000001', None],
        ['BetaNet ', '0.770000', '0.100000', None],
        ['betanet', '0.780000', '0.100000', None],
    ])
    rng.shuffle(rows)
    accuracies = [row[3] for row in rows if row[3] is not None]
    lines = ['id,model_name,accuracy,loss']
    for i, row in enumerate(rows, 1):
        lines.append(f'{i},{row[0]},{row[1]},{row[2]}')
    return '\n'.join(lines) + '\n', accuracies


def main():
    assert CPP_PATH.is_file(), f'C++ source code {CPP_PATH} is missing.'

    # Compile the submitted source rather than trusting a pre-created binary.
    run(['g++', '-std=c++17', str(CPP_PATH), '-o', str(BIN_PATH)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert BIN_PATH.is_file(), f'Compiled binary {BIN_PATH} is missing.'

    original_csv = CSV_PATH.read_bytes()
    try:
        # Preserve and exercise all checks made by the original verifier.
        original_content = execute_submission()
        check_original_assertions(original_content)
        parse_strict_report(original_content)

        # Exercise filtering and bootstrap behavior on unpredictable inputs.
        for valid_count in (1, 5, 11):
            csv_text, accuracies = make_case(valid_count)
            CSV_PATH.write_text(csv_text)
            content = execute_submission()
            count, mean, lower, upper = parse_strict_report(content)
            expected_mean, expected_lower, expected_upper = oracle_values(accuracies)
            assert count == len(accuracies), f'Expected {len(accuracies)} valid rows, got {count}.'
            tolerance = 0.000051
            assert abs(mean - expected_mean) <= tolerance, f'Incorrect bootstrap mean: got {mean}, expected {expected_mean:.4f}.'
            assert abs(lower - expected_lower) <= tolerance, f'Incorrect lower CI bound: got {lower}, expected {expected_lower:.4f}.'
            assert abs(upper - expected_upper) <= tolerance, f'Incorrect upper CI bound: got {upper}, expected {expected_upper:.4f}.'
    finally:
        CSV_PATH.write_bytes(original_csv)


if __name__ == '__main__':
    main()
PY_EOF

cat << 'CPP_EOF' > /tmp/bootstrap_oracle.cpp
#include <algorithm>
#include <cstddef>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>

int main() {
    std::size_t n;
    if (!(std::cin >> n) || n == 0) return 2;
    std::vector<double> values(n);
    for (double &v : values) std::cin >> v;

    std::mt19937 gen(42);
    std::uniform_int_distribution<std::size_t> dist(0, n - 1);
    std::vector<double> means;
    means.reserve(10000);
    double mean_sum = 0.0;
    for (int sample = 0; sample < 10000; ++sample) {
        double sum = 0.0;
        for (std::size_t draw = 0; draw < n; ++draw) sum += values[dist(gen)];
        double mean = sum / static_cast<double>(n);
        means.push_back(mean);
        mean_sum += mean;
    }
    std::sort(means.begin(), means.end());
    std::cout << std::setprecision(17)
              << mean_sum / 10000.0 << ' '
              << means[250] << ' ' << means[9750] << '\n';
}
CPP_EOF

g++ -std=c++17 /tmp/bootstrap_oracle.cpp -o /tmp/bootstrap_oracle

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
