#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import sys
import tempfile

TRUSTED_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double randn() {
    double u1 = ((double) rand() / RAND_MAX);
    double u2 = ((double) rand() / RAND_MAX);
    if (u1 <= 0.0) u1 = 1e-7;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <seed> <N>\n", argv[0]);
        return 1;
    }
    int seed = atoi(argv[1]);
    int N = atoi(argv[2]);
    srand(seed);

    for (int i = 0; i < N; i++) {
        double val = randn() * 1.5 + 0.5;
        // Artifact introduced by mesh size N
        val += 500.0 / N;
        printf("%.6f\n", val);
    }
    return 0;
}
'''

def test_executable_exists():
    executable_path = "/home/user/sim/sim"
    assert os.path.isfile(executable_path), f"The compiled executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"The file {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {executable_path} is not a compiled ELF executable."

def test_output_files_exist():
    coarse_path = "/home/user/coarse.txt"
    fine_path = "/home/user/fine.txt"

    assert os.path.isfile(coarse_path), f"The file {coarse_path} does not exist."
    assert os.path.isfile(fine_path), f"The file {fine_path} does not exist."

    with open(coarse_path, "r") as f:
        coarse_lines = f.read().splitlines()
    assert len(coarse_lines) == 1000, f"Expected 1000 lines in {coarse_path}, found {len(coarse_lines)}."

    with open(fine_path, "r") as f:
        fine_lines = f.read().splitlines()
    assert len(fine_lines) == 2000, f"Expected 2000 lines in {fine_path}, found {len(fine_lines)}."

def test_simulator_was_run_with_required_inputs():
    executable_path = "/home/user/sim/sim"

    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = os.path.join(tmpdir, "sim.c")
        reference_path = os.path.join(tmpdir, "sim_reference")
        with open(source_path, "w") as f:
            f.write(TRUSTED_SOURCE)

        compiled = subprocess.run(
            ["gcc", source_path, "-o", reference_path, "-lm"],
            capture_output=True,
            text=True,
        )
        assert compiled.returncode == 0, f"Verifier failed to compile the trusted simulator: {compiled.stderr}"

        for n, saved_path in ((1000, "/home/user/coarse.txt"), (2000, "/home/user/fine.txt")):
            expected = subprocess.run(
                [reference_path, "42", str(n)],
                capture_output=True,
                timeout=30,
            )
            assert expected.returncode == 0, f"Trusted simulator failed for N={n}: {expected.stderr!r}"

            actual_run = subprocess.run(
                [executable_path, "42", str(n)],
                capture_output=True,
                timeout=30,
            )
            assert actual_run.returncode == 0, f"Submitted simulator failed for seed 42, N={n}: {actual_run.stderr!r}"
            assert actual_run.stdout == expected.stdout, f"Submitted simulator output is incorrect for seed 42, N={n}."

            with open(saved_path, "rb") as f:
                saved = f.read()
            assert saved == actual_run.stdout, f"{saved_path} is not the output of the submitted simulator run with seed 42 and N={n}."

def test_results_json():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"The file {results_path} does not exist."

    with open(results_path, "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {results_path} does not contain valid JSON."

    expected_keys = {"distance", "ci_lower", "ci_upper"}
    assert set(actual.keys()) == expected_keys, f"Expected keys {expected_keys} in {results_path}, found {set(actual.keys())}."

    script = """
import numpy as np
from scipy.stats import wasserstein_distance
import json

coarse = np.loadtxt("/home/user/coarse.txt")
fine = np.loadtxt("/home/user/fine.txt")

dist = wasserstein_distance(coarse, fine)

np.random.seed(42)
boot_dists = []
for _ in range(1000):
    c_boot = np.random.choice(coarse, size=len(coarse), replace=True)
    f_boot = np.random.choice(fine, size=len(fine), replace=True)
    boot_dists.append(wasserstein_distance(c_boot, f_boot))

ci_lower = np.percentile(boot_dists, 2.5)
ci_upper = np.percentile(boot_dists, 97.5)

print(json.dumps({
    "distance": round(dist, 4),
    "ci_lower": round(ci_lower, 4),
    "ci_upper": round(ci_upper, 4)
}))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to compute expected values. Ensure numpy and scipy are installed. Error: {result.stderr}"

    expected = json.loads(result.stdout)

    for key in expected_keys:
        assert isinstance(actual[key], (int, float)), f"Value for {key} must be a number."
        diff = abs(actual[key] - expected[key])
        assert diff <= 1e-4, f"Value for {key} is incorrect. Expected {expected[key]}, got {actual[key]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
