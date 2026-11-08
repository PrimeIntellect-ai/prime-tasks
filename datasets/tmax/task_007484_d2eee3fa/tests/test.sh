#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/diffusion")
SOURCE = PROJECT / "mc_diffusion.cpp"
SCRIPT = PROJECT / "test_convergence.sh"
EXECUTABLE = PROJECT / "mc_diffusion"
LOG = PROJECT / "convergence.log"
STUDENT_EXECUTABLE = Path("/tmp/mc_diffusion_student")
ORACLE_SOURCE = Path("/tmp/mc_diffusion_oracle.cpp")
ORACLE_EXECUTABLE = Path("/tmp/mc_diffusion_oracle")

ORACLE_CODE = r'''#include <algorithm>
#include <iostream>
#include <random>
#include <vector>

int main(int argc, char** argv) {
    if (argc != 4) return 1;

    int N = std::stoi(argv[1]);
    int T = std::stoi(argv[2]);
    int seed = std::stoi(argv[3]);
    if (N <= 0 || T < 0) return 1;

    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> move(0, 1);
    std::vector<int> squared_displacements;
    squared_displacements.reserve(N);
    double total = 0.0;

    for (int i = 0; i < N; ++i) {
        int x = 0, y = 0, z = 0;
        for (int t = 0; t < T; ++t) {
            x += move(rng) ? 1 : -1;
            y += move(rng) ? 1 : -1;
            z += move(rng) ? 1 : -1;
        }
        int sd = x * x + y * y + z * z;
        squared_displacements.push_back(sd);
        total += sd;
    }

    double msd = total / N;
    rng.seed(seed + 1);
    std::uniform_int_distribution<int> index(0, N - 1);
    std::vector<double> bootstrap_means;
    bootstrap_means.reserve(1000);

    for (int b = 0; b < 1000; ++b) {
        double bootstrap_total = 0.0;
        for (int j = 0; j < N; ++j) {
            bootstrap_total += squared_displacements[index(rng)];
        }
        bootstrap_means.push_back(bootstrap_total / N);
    }

    std::sort(bootstrap_means.begin(), bootstrap_means.end());
    std::cout << "MSD: " << msd << ", CI: ["
              << bootstrap_means[24] << ", " << bootstrap_means[974] << "]\n";
    return 0;
}
'''


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, text=True, capture_output=True,
                          timeout=120, **kwargs)


@pytest.fixture(scope="session")
def oracle():
    ORACLE_SOURCE.write_text(ORACLE_CODE)
    result = subprocess.run(
        ["g++", "-O3", "-std=c++17", str(ORACLE_SOURCE), "-o", str(ORACLE_EXECUTABLE)],
        text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, f"Verifier oracle failed to compile: {result.stderr}"
    return ORACLE_EXECUTABLE


def expected_output(oracle, n, t, seed):
    return run_checked([str(oracle), str(n), str(t), str(seed)]).stdout


def test_diffusion_directory_exists():
    """Check that the diffusion directory was created."""
    assert os.path.isdir("/home/user/diffusion"), "/home/user/diffusion directory is missing."


def test_source_files_exist():
    """Check that the C++ source and bash script exist."""
    assert os.path.isfile("/home/user/diffusion/mc_diffusion.cpp"), "mc_diffusion.cpp is missing."
    assert os.path.isfile("/home/user/diffusion/test_convergence.sh"), "test_convergence.sh is missing."


def test_executable_exists():
    """Check that the C++ program was compiled into an executable."""
    exe_path = "/home/user/diffusion/mc_diffusion"
    assert os.path.isfile(exe_path), "Compiled executable mc_diffusion is missing."
    assert os.access(exe_path, os.X_OK), "mc_diffusion is not executable."


def test_source_compiles_and_matches_specification(oracle):
    """Compile the submitted source and compare deterministic results to the specification."""
    result = subprocess.run(
        ["g++", "-O3", "-std=c++17", str(SOURCE), "-o", str(STUDENT_EXECUTABLE)],
        text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, f"mc_diffusion.cpp failed to compile: {result.stderr}"

    cases = [(7, 9, 123), (31, 20, 0), (257, 37, 98765)]
    for n, t, seed in cases:
        actual = run_checked([str(STUDENT_EXECUTABLE), str(n), str(t), str(seed)]).stdout
        expected = expected_output(oracle, n, t, seed)
        assert actual == expected, (
            f"Incorrect output for N={n}, T={t}, seed={seed}. "
            f"Expected {expected!r}, got {actual!r}."
        )


def test_convergence_script_executes_and_recreates_artifacts(oracle):
    """Run the submitted regression script and validate the artifacts it generates."""
    if EXECUTABLE.exists() or EXECUTABLE.is_symlink():
        EXECUTABLE.unlink()
    if LOG.exists() or LOG.is_symlink():
        LOG.unlink()

    result = subprocess.run(
        ["bash", str(SCRIPT)], cwd=str(PROJECT), text=True,
        capture_output=True, timeout=180
    )
    assert result.returncode == 0, f"test_convergence.sh failed: {result.stderr}"
    assert EXECUTABLE.is_file(), "test_convergence.sh did not build mc_diffusion."
    assert os.access(EXECUTABLE, os.X_OK), "The rebuilt mc_diffusion is not executable."
    assert LOG.is_file(), "test_convergence.sh did not generate convergence.log."

    expected_lines = [expected_output(oracle, n, 100, 42).rstrip("\n") for n in (100, 1000, 10000)]
    actual_lines = LOG.read_text().splitlines()
    assert actual_lines == expected_lines, (
        "convergence.log does not contain the exact outputs for "
        "N=100, 1000, and 10000 with T=100 and seed=42."
    )

    for n in (100, 1000, 10000):
        actual = run_checked([str(EXECUTABLE), str(n), "100", "42"]).stdout
        expected = expected_output(oracle, n, 100, 42)
        assert actual == expected, f"Rebuilt executable is incorrect for N={n}."


def test_convergence_log():
    """Check the contents of convergence.log for correctness and convergence."""
    log_path = "/home/user/diffusion/convergence.log"
    assert os.path.isfile(log_path), "convergence.log is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in convergence.log, found {len(lines)}."

    pattern = re.compile(r"^MSD:\s*([0-9.]+),\s*CI:\s*\[([0-9.]+),\s*([0-9.]+)\]$")

    widths = []
    for i, line in enumerate(lines):
        match = pattern.match(line)
        assert match, f"Line {i+1} does not match expected format: {line}"

        msd = float(match.group(1))
        lower = float(match.group(2))
        upper = float(match.group(3))

        assert 200 <= msd <= 400, f"Line {i+1} MSD ({msd}) is not near the expected value of 300."
        assert lower <= msd <= upper, f"Line {i+1} MSD ({msd}) is not within CI [{lower}, {upper}]."

        widths.append(upper - lower)

    assert widths[0] > widths[1], f"CI width did not decrease from N=100 ({widths[0]}) to N=1000 ({widths[1]})."
    assert widths[1] > widths[2], f"CI width did not decrease from N=1000 ({widths[1]}) to N=10000 ({widths[2]})."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
