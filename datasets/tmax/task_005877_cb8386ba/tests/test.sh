#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from pathlib import Path
import pytest

CANONICAL_SOURCE = '''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    int n = 1000;
    // Hardcoded seed for deterministic data generation
    srand(1042);
    for(int i = 0; i < n; i++) {
        // Generate values from a simulated skewed distribution
        double u1 = (double)rand() / RAND_MAX;
        double u2 = (double)rand() / RAND_MAX;
        double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
        double val = exp(z0 * 0.5 + 2.0); // Log-normalish
        printf("%.6f\\n", val);
    }
    return 0;
}
'''


def trusted_generator_output(tmp_path):
    source = tmp_path / "generate_data.c"
    executable = tmp_path / "generate_data"
    source.write_text(CANONICAL_SOURCE)
    subprocess.run(
        ["gcc", str(source), "-o", str(executable), "-lm"],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return subprocess.run(
        [str(executable)], check=True, capture_output=True, timeout=30
    ).stdout


def run_bootstrap_script():
    return subprocess.run(
        ["/home/user/venv/bin/python", "/home/user/bootstrap_ci.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )


def independently_compute_expected(data_path):
    script = f'''
import numpy as np

data = np.loadtxt({str(data_path)!r})
np.random.seed(42)
n = len(data)
n_bootstraps = 10000

bootstrapped_medians = []
for _ in range(n_bootstraps):
    sample = np.random.choice(data, size=n, replace=True)
    bootstrapped_medians.append(np.median(sample))

lower = np.percentile(bootstrapped_medians, 2.5)
upper = np.percentile(bootstrapped_medians, 97.5)

print(f"Lower: {{lower:.4f}}")
print(f"Upper: {{upper:.4f}}")
'''
    try:
        result = subprocess.run(
            ["/home/user/venv/bin/python", "-c", script],
            capture_output=True,
            text=True,
            check=True,
            timeout=120,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected results using the virtual environment. Is numpy installed? Error: {e.stderr}")
    return result.stdout.strip().split("\n")


def assert_results_match(data_path):
    results_path = Path("/home/user/ci_results.txt")
    assert results_path.exists(), f"Results file {results_path} does not exist."
    actual_output = results_path.read_text().strip().split("\n")
    expected_output = independently_compute_expected(data_path)

    assert len(actual_output) == 2, f"Expected 2 lines in {results_path}, found {len(actual_output)}."
    assert actual_output[0].strip() == expected_output[0].strip(), (
        f"Lower bound mismatch. Expected '{expected_output[0].strip()}', got '{actual_output[0].strip()}'."
    )
    assert actual_output[1].strip() == expected_output[1].strip(), (
        f"Upper bound mismatch. Expected '{expected_output[1].strip()}', got '{actual_output[1].strip()}'."
    )


def test_executable_exists_and_runs_supplied_generator(tmp_path):
    exe_path = Path("/home/user/generate_data")
    source_path = Path("/home/user/generate_data.c")
    assert exe_path.exists(), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    assert source_path.read_text() == CANONICAL_SOURCE, "The supplied C generator source was modified."
    assert exe_path.read_bytes()[:4] == b"\x7fELF", f"{exe_path} is not a compiled native executable."

    expected = trusted_generator_output(tmp_path)
    result = subprocess.run(
        [str(exe_path)], cwd="/home/user", capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"Generator exited with status {result.returncode}."
    assert result.stdout == expected, "Compiled generator output does not match the supplied C program."


def test_sensor_data_exists_and_matches_generator(tmp_path):
    data_path = Path("/home/user/sensor_data.txt")
    assert data_path.exists(), f"Data file {data_path} does not exist."
    lines = data_path.read_text().splitlines()
    assert len(lines) == 1000, f"Expected 1000 lines in {data_path}, found {len(lines)}."

    expected = trusted_generator_output(tmp_path)
    generated = subprocess.run(
        ["/home/user/generate_data"],
        cwd="/home/user",
        capture_output=True,
        check=True,
        timeout=30,
    ).stdout
    assert data_path.read_bytes() == generated, "sensor_data.txt was not produced by the submitted generator."
    assert generated == expected, "sensor_data.txt does not contain the supplied generator's readings."


def test_venv_exists():
    python_path = "/home/user/venv/bin/python"
    assert os.path.exists(python_path), f"Virtual environment Python {python_path} does not exist."
    subprocess.run(
        [python_path, "-c", "import numpy"],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_ci_results_are_produced_by_script():
    script_path = Path("/home/user/bootstrap_ci.py")
    results_path = Path("/home/user/ci_results.txt")
    assert script_path.is_file(), f"Bootstrap script {script_path} does not exist."
    assert results_path.exists(), f"Results file {results_path} does not exist."

    results_path.unlink()
    result = run_bootstrap_script()
    assert result.returncode == 0, f"bootstrap_ci.py failed: {result.stderr}"
    assert results_path.exists(), "bootstrap_ci.py did not create ci_results.txt."
    assert_results_match("/home/user/sensor_data.txt")


def test_bootstrap_script_handles_unseen_data():
    data_path = Path("/home/user/sensor_data.txt")
    results_path = Path("/home/user/ci_results.txt")
    original_data = data_path.read_bytes()
    original_results = results_path.read_bytes() if results_path.exists() else None

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    values = [round(rng.uniform(-200.0, 300.0) + (i % 17) * 0.137, 6) for i in range(1000)]

    try:
        data_path.write_text("".join(f"{value:.6f}\n" for value in values))
        if results_path.exists():
            results_path.unlink()
        result = run_bootstrap_script()
        assert result.returncode == 0, f"bootstrap_ci.py failed on unseen data: {result.stderr}"
        assert results_path.exists(), "bootstrap_ci.py did not create results for unseen data."
        assert_results_match(data_path)
    finally:
        data_path.write_bytes(original_data)
        if original_results is None:
            if results_path.exists():
                results_path.unlink()
        else:
            results_path.write_bytes(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
