#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import textwrap

import pytest

CPP_PATH = "/home/user/analysis.cpp"
METRICS_PATH = "/home/user/metrics.json"
FEATURES_PATH = "/home/user/data/features.csv"
AUDIO_PATH = "/app/experiment_targets.wav"


@pytest.fixture(scope="session", autouse=True)
def build_run_and_compute_reference():
    assert os.path.isfile(CPP_PATH), f"Missing C++ analysis file: {CPP_PATH}"
    assert os.path.isfile(FEATURES_PATH), f"Missing feature file: {FEATURES_PATH}"
    assert os.path.isfile(AUDIO_PATH), f"Missing audio file: {AUDIO_PATH}"
    assert os.path.getsize(AUDIO_PATH) > 44, "Audio target file is empty or invalid"

    with open(FEATURES_PATH) as f:
        rows = [line.strip() for line in f if line.strip()]
    assert len(rows) == 50, f"Expected 50 X values, found {len(rows)}"
    try:
        actual_xs = [float(v) for v in rows]
    except ValueError:
        pytest.fail("features.csv contains a non-numeric value")
    assert all(math.isfinite(v) for v in actual_xs), "features.csv contains a non-finite value"

    rng = random.Random(42)
    expected_xs = []
    expected_ys = []
    for _ in range(50):
        x = round(rng.uniform(0, 10), 2)
        y = round(x * 1.5 + rng.uniform(-2, 2), 2)
        expected_xs.append(x)
        expected_ys.append(y)
    assert actual_xs == expected_xs, "features.csv was altered from the experiment data"

    binary = "/tmp/agent_analysis"
    compiled = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", binary],
        text=True, capture_output=True, timeout=30
    )
    assert compiled.returncode == 0, "analysis.cpp failed to compile:\n" + compiled.stderr

    if os.path.exists(METRICS_PATH):
        os.unlink(METRICS_PATH)
    executed = subprocess.run(
        [binary], cwd="/home/user", text=True, capture_output=True, timeout=30
    )
    assert executed.returncode == 0, (
        "Compiled analysis program failed:\nstdout:\n" + executed.stdout +
        "\nstderr:\n" + executed.stderr
    )
    assert os.path.isfile(METRICS_PATH), "Running analysis.cpp did not create /home/user/metrics.json"

    dataset = "/tmp/verifier_xy.csv"
    with open(dataset, "w") as f:
        for x, y in zip(actual_xs, expected_ys):
            f.write(f"{x:.17g} {y:.17g}\n")

    reference_source = r'''
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>

static double corr(const std::vector<double>& x, const std::vector<double>& y) {
    const size_t n = x.size();
    double mx = 0.0, my = 0.0;
    for (size_t i = 0; i < n; ++i) { mx += x[i]; my += y[i]; }
    mx /= n; my /= n;
    double num = 0.0, dx = 0.0, dy = 0.0;
    for (size_t i = 0; i < n; ++i) {
        double a = x[i] - mx, b = y[i] - my;
        num += a * b; dx += a * a; dy += b * b;
    }
    return num / std::sqrt(dx * dy);
}

int main() {
    std::ifstream in("/tmp/verifier_xy.csv");
    std::vector<double> x, y;
    double a, b;
    while (in >> a >> b) { x.push_back(a); y.push_back(b); }
    if (x.size() != 50) return 2;
    std::mt19937 gen(42);
    std::uniform_int_distribution<int> pick(0, 49);
    std::vector<double> values;
    values.reserve(10000);
    std::vector<double> bx(50), by(50);
    for (int iter = 0; iter < 10000; ++iter) {
        for (int i = 0; i < 50; ++i) {
            int j = pick(gen); bx[i] = x[j]; by[i] = y[j];
        }
        values.push_back(corr(bx, by));
    }
    std::sort(values.begin(), values.end());
    double lp = 0.025 * (values.size() - 1);
    double up = 0.975 * (values.size() - 1);
    auto interp = [&](double p) {
        size_t lo = static_cast<size_t>(std::floor(p));
        size_t hi = static_cast<size_t>(std::ceil(p));
        return values[lo] + (p - lo) * (values[hi] - values[lo]);
    };
    std::cout << std::setprecision(17)
              << values[249] << " " << values[250] << " " << interp(lp) << " "
              << values[9749] << " " << values[9750] << " " << interp(up) << "\n";
}
'''
    reference_cpp = "/tmp/reference_bootstrap.cpp"
    reference_bin = "/tmp/reference_bootstrap"
    with open(reference_cpp, "w") as f:
        f.write(reference_source)
    ref_compile = subprocess.run(
        ["g++", "-std=c++17", "-O2", reference_cpp, "-o", reference_bin],
        text=True, capture_output=True, timeout=30
    )
    assert ref_compile.returncode == 0, "Verifier reference calculation failed to compile"
    ref_run = subprocess.run(
        [reference_bin], text=True, capture_output=True, timeout=30
    )
    assert ref_run.returncode == 0, "Verifier reference calculation failed"
    values = [float(v) for v in ref_run.stdout.split()]
    assert len(values) == 6
    return {"lower": values[:3], "upper": values[3:]}


def test_metrics_json_exists_format_and_values(build_run_and_compute_reference):
    assert os.path.isfile(METRICS_PATH), f"Missing metrics file: {METRICS_PATH}"
    with open(METRICS_PATH) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} is not valid JSON.")

    assert "ci_lower" in data, "metrics.json missing 'ci_lower'"
    assert "ci_upper" in data, "metrics.json missing 'ci_upper'"
    try:
        agent_lower = float(data["ci_lower"])
        agent_upper = float(data["ci_upper"])
    except (ValueError, TypeError):
        pytest.fail("ci_lower and ci_upper must be numeric.")

    assert math.isfinite(agent_lower) and math.isfinite(agent_upper), "CI bounds must be finite"
    assert -1.0 <= agent_lower <= 1.0, f"ci_lower {agent_lower} is out of valid Pearson correlation bounds [-1, 1]"
    assert -1.0 <= agent_upper <= 1.0, f"ci_upper {agent_upper} is out of valid Pearson correlation bounds [-1, 1]"
    assert agent_lower < agent_upper, f"ci_lower ({agent_lower}) must be less than ci_upper ({agent_upper})"

    expected = build_run_and_compute_reference
    tolerance = 5e-4
    assert min(abs(agent_lower - v) for v in expected["lower"]) <= tolerance, (
        f"ci_lower {agent_lower} does not match the recomputed seeded bootstrap CI"
    )
    assert min(abs(agent_upper - v) for v in expected["upper"]) <= tolerance, (
        f"ci_upper {agent_upper} does not match the recomputed seeded bootstrap CI"
    )


def test_cpp_code_exists():
    assert os.path.isfile(CPP_PATH), f"Missing C++ analysis file: {CPP_PATH}"
    with open(CPP_PATH) as f:
        content = f.read()
    assert "mt19937" in content or "std::mt19937" in content, "C++ code does not seem to use mt19937 for random number generation."
    assert "42" in content, "C++ code does not seem to use the seed 42."
    assert "10000" in content or "10,000" in content or "10000.0" in content, "C++ code does not seem to use B=10000 bootstrap iterations."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
