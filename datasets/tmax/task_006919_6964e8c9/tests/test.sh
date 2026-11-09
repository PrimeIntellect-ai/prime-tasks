#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import tempfile


def test_cpp_file_exists():
    path = '/home/user/validate_etl.cpp'
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_executable_exists():
    path = '/home/user/validate_etl'
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_json_output():
    path = '/home/user/validation_result.json'
    assert os.path.exists(path), f"JSON output file {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, 'r') as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    assert "status" in res, "Missing 'status' key in JSON output."
    assert "r_point" in res, "Missing 'r_point' key in JSON output."
    assert "ci_lower" in res, "Missing 'ci_lower' key in JSON output."
    assert "ci_upper" in res, "Missing 'ci_upper' key in JSON output."

    assert res["status"] == "INVALID", f"Expected status 'INVALID', got '{res['status']}'"

    assert math.isclose(res["r_point"], 0.7844, abs_tol=0.001), f"Expected r_point ~0.7844, got {res['r_point']}"
    assert math.isclose(res["ci_lower"], 0.7513, abs_tol=0.005), f"Expected ci_lower ~0.7513, got {res['ci_lower']}"
    assert math.isclose(res["ci_upper"], 0.8146, abs_tol=0.005), f"Expected ci_upper ~0.8146, got {res['ci_upper']}"


def run_program(executable, args):
    try:
        proc = subprocess.run(
            [executable] + [str(x) for x in args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        assert False, f"{executable} timed out"
    assert proc.returncode == 0, (
        f"{executable} exited with {proc.returncode}. stderr: {proc.stderr}"
    )
    return proc.stdout


def pearson(rows):
    mx = sum(x for x, _ in rows) / len(rows)
    my = sum(y for _, y in rows) / len(rows)
    num = sum((x - mx) * (y - my) for x, y in rows)
    dx = sum((x - mx) ** 2 for x, _ in rows)
    dy = sum((y - my) ** 2 for _, y in rows)
    return num / math.sqrt(dx * dy)


def test_program_behavior_and_source_build():
    rebuilt = '/tmp/submission_validate_etl'
    build = subprocess.run(
        ['g++', '-std=c++17', '-O3', '/home/user/validate_etl.cpp', '-o', rebuilt],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, f"Submitted C++ source does not compile: {build.stderr}"

    reference_source = r'''#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

static double correlation(const std::vector<std::pair<double, double>>& data) {
    double sx = 0.0, sy = 0.0;
    for (const auto& p : data) { sx += p.first; sy += p.second; }
    const double mx = sx / data.size();
    const double my = sy / data.size();
    double num = 0.0, dx = 0.0, dy = 0.0;
    for (const auto& p : data) {
        const double x = p.first - mx;
        const double y = p.second - my;
        num += x * y;
        dx += x * x;
        dy += y * y;
    }
    return num / std::sqrt(dx * dy);
}

int main(int argc, char** argv) {
    if (argc != 5) return 2;
    std::ifstream in(argv[1]);
    if (!in) return 3;
    std::string line;
    std::getline(in, line);
    std::vector<std::pair<double, double>> data;
    while (std::getline(in, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string a, b;
        if (!std::getline(ss, a, ',') || !std::getline(ss, b)) return 4;
        data.emplace_back(std::stod(a), std::stod(b));
    }
    if (data.empty()) return 5;
    const double expected = std::stod(argv[2]);
    const int bootstraps = std::stoi(argv[3]);
    const unsigned int seed = static_cast<unsigned int>(std::stoul(argv[4]));
    const double point = correlation(data);
    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> dist(0, static_cast<int>(data.size()) - 1);
    std::vector<double> values;
    values.reserve(bootstraps);
    std::vector<std::pair<double, double>> sample(data.size());
    for (int i = 0; i < bootstraps; ++i) {
        for (std::size_t j = 0; j < data.size(); ++j) sample[j] = data[dist(rng)];
        values.push_back(correlation(sample));
    }
    std::sort(values.begin(), values.end());
    const double lower = values[static_cast<int>(std::floor(0.025 * bootstraps))];
    const double upper = values[static_cast<int>(std::floor(0.975 * bootstraps))];
    const char* status = (expected > lower && expected < upper) ? "VALID" : "INVALID";
    std::cout << std::fixed << std::setprecision(4)
              << "{\n"
              << "  \"status\": \"" << status << "\",\n"
              << "  \"r_point\": " << point << ",\n"
              << "  \"ci_lower\": " << lower << ",\n"
              << "  \"ci_upper\": " << upper << "\n"
              << "}\n";
    return 0;
}
'''

    with tempfile.TemporaryDirectory(prefix='etl_behavior_') as td:
        cases = [('/home/user/etl_output.csv', '0.75', '2000', '42')]
        rng = random.Random(int.from_bytes(os.urandom(16), 'big'))

        specifications = [
            (29, 0.85, 0.45, True, 137),
            (43, -0.70, 0.65, False, 211),
            (61, 0.45, 1.10, True, 263),
        ]
        for case_number, (n, slope, noise, expect_inside, boots) in enumerate(specifications):
            rows = []
            for i in range(n):
                x = rng.gauss(0.0, 1.0) + 0.03 * i
                y = slope * x + rng.gauss(0.0, noise) + 0.01 * (i % 5)
                rows.append((x, y))
            csv_path = os.path.join(td, f'case_{case_number}.csv')
            with open(csv_path, 'w') as f:
                f.write('val1,val2\n')
                for x, y in rows:
                    f.write(f'{x:.8f},{y:.8f}\n')
            parsed_rows = [(float(f'{x:.8f}'), float(f'{y:.8f}')) for x, y in rows]
            if expect_inside:
                expected = pearson(parsed_rows)
            else:
                expected = -0.99 if pearson(parsed_rows) > 0 else 0.99
            seed = rng.randrange(0, 2**32)
            cases.append((csv_path, format(expected, '.17g'), str(boots), str(seed)))

        # Execute both the delivered artifact and an independent build of the source
        # before creating the reference executable.
        observed = {}
        for executable in ['/home/user/validate_etl', rebuilt]:
            observed[executable] = [run_program(executable, case) for case in cases]

        with open('/home/user/validation_result.json', 'r') as f:
            saved_result = f.read()
        assert observed['/home/user/validate_etl'][0] == saved_result, (
            'validation_result.json is not the output produced by validate_etl for the required arguments'
        )

        reference_cpp = os.path.join(td, 'reference.cpp')
        reference_exe = os.path.join(td, 'reference')
        with open(reference_cpp, 'w') as f:
            f.write(reference_source)
        ref_build = subprocess.run(
            ['g++', '-std=c++17', '-O3', reference_cpp, '-o', reference_exe],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert ref_build.returncode == 0, f"Internal reference failed to compile: {ref_build.stderr}"

        expected_outputs = [run_program(reference_exe, case) for case in cases]
        for executable, outputs in observed.items():
            for index, (actual, expected) in enumerate(zip(outputs, expected_outputs)):
                assert actual == expected, (
                    f"{executable} produced an incorrect or improperly formatted result "
                    f"for behavioral case {index}.\nExpected:\n{expected}\nActual:\n{actual}"
                )
                parsed = json.loads(actual)
                assert list(parsed.keys()) == ['status', 'r_point', 'ci_lower', 'ci_upper']
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
