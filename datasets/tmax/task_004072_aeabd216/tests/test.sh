#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

SCRIPT = "/home/user/run_pipeline.sh"
SOURCE = "/home/user/posterior_estimation.cpp"
RESULTS = "/home/user/results.txt"
SAMPLER = "/home/user/sampler"


def parse_results(content):
    lines = content.splitlines()
    assert len(lines) == 3, "results.txt must contain exactly three lines"
    patterns = [
        r"MAP_MU:\s*([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)",
        r"MCMC_MEAN:\s*([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)",
        r"MCMC_VAR:\s*([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)",
    ]
    values = []
    for line, pattern in zip(lines, patterns):
        match = re.fullmatch(pattern, line.strip())
        assert match is not None, f"Incorrect results.txt line: {line!r}"
        value = float(match.group(1))
        assert math.isfinite(value), "Results must be finite numbers"
        values.append(value)
    return tuple(values)


def read_results():
    assert os.path.exists(RESULTS), f"{RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        return parse_results(f.read())


def test_complete_pipeline():
    # Preserve the original artifact checks.
    assert os.path.exists(SCRIPT), f"{SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."

    with open(SCRIPT, "r", errors="replace") as f:
        script_text = f.read()
    assert "g++" in script_text, "run_pipeline.sh must compile with g++."
    assert re.search(r"-std=(?:c\+\+|gnu\+\+)17\b", script_text), \
        "run_pipeline.sh must request C++17."

    # Force the submitted script to recreate both the binary and results.
    for path in (RESULTS, SAMPLER):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run([SCRIPT], cwd="/home/user", check=True, timeout=60)

    assert os.path.isfile(SAMPLER), "run_pipeline.sh did not create sampler."
    assert os.access(SAMPLER, os.X_OK), "sampler is not executable."
    with open(SAMPLER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sampler is not a compiled executable."
    pipeline_values = read_results()

    # Independently compile and execute the submitted C++ source. This prevents
    # the shell script or a pre-existing results file from self-reporting values.
    direct_binary = "/tmp/independently_compiled_sampler"
    subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", direct_binary],
        check=True,
        timeout=60,
    )
    os.remove(RESULTS)
    subprocess.run([direct_binary], cwd="/home/user", check=True, timeout=60)
    direct_values = read_results()

    for from_pipeline, from_source in zip(pipeline_values, direct_values):
        assert abs(from_pipeline - from_source) < 1e-6, \
            "run_pipeline.sh output does not match the submitted C++ program."

    # Derive the deterministic MAP target from the specified RNG and data model.
    reference_source = r'''
#include <cmath>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>
int main() {
    std::mt19937 rng(42);
    std::normal_distribution<double> data_dist(5.0, 1.0);
    std::vector<double> x(50);
    double sum = 0.0;
    for (double &v : x) { v = data_dist(rng); sum += v; }
    double mu = 0.0;
    for (int iter = 0; iter < 100; ++iter) {
        double gradient = -mu / 100.0;
        for (double v : x) gradient += v - mu;
        mu += 0.01 * gradient;
    }
    std::cout << std::setprecision(17) << mu << " "
              << sum / 50.01 << " " << 1.0 / 50.01 << "\n";
}
'''
    ref_cpp = "/tmp/reference_map.cpp"
    ref_bin = "/tmp/reference_map"
    with open(ref_cpp, "w") as f:
        f.write(reference_source)
    subprocess.run(["g++", "-std=c++17", ref_cpp, "-o", ref_bin], check=True, timeout=60)
    ref_output = subprocess.check_output([ref_bin], text=True, timeout=10)
    expected_map, posterior_mean, posterior_var = map(float, ref_output.split())

    map_mu, mcmc_mean, mcmc_var = direct_values
    assert abs(map_mu - expected_map) < 2e-5, \
        f"MAP_MU ({map_mu}) does not match the specified gradient-ascent result ({expected_map})."

    # Preserve the original mathematical assertions.
    assert abs(mcmc_var - 0.02) < 0.005, \
        f"MCMC_VAR ({mcmc_var}) is not close to theoretical variance 0.02."
    assert abs(map_mu - mcmc_mean) < 0.01, \
        f"MAP_MU ({map_mu}) and MCMC_MEAN ({mcmc_mean}) differ by more than 0.01."
    assert abs(map_mu - 5.0) < 0.5, \
        f"MAP_MU ({map_mu}) is not close enough to the true parameter 5.0."

    # Also compare against posterior quantities derived from the generated data.
    assert abs(mcmc_mean - posterior_mean) < 0.01, \
        "MCMC_MEAN is inconsistent with the posterior for the specified data."
    assert abs(mcmc_var - posterior_var) < 0.005, \
        "MCMC_VAR is inconsistent with the specified posterior."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
