#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import pytest

CPP_FILE = "/home/user/mcmc_sequence.cpp"
EIGEN_DIR = "/home/user/eigen-3.4.0"
EXE_FILE = "/home/user/mcmc_sequence"
CSV_FILE = "/home/user/posterior_mean.csv"


def test_eigen_extracted():
    """Test that Eigen library is extracted to the correct location."""
    assert os.path.isdir(EIGEN_DIR), f"Directory {EIGEN_DIR} does not exist."
    eigen_dense = os.path.join(EIGEN_DIR, "Eigen", "Dense")
    assert os.path.isfile(eigen_dense), f"Eigen headers not found at {eigen_dense}. Make sure it is extracted correctly."


def test_cpp_code_fixed():
    """Test that the C++ code uses Cholesky decomposition and removes the bug."""
    assert os.path.isfile(CPP_FILE), f"File {CPP_FILE} does not exist."

    with open(CPP_FILE, "r") as f:
        content = f.read()

    assert "llt" in content.lower() or "LLT" in content, "Cholesky decomposition (LLT) not used in the C++ file."
    assert "covariance * z" not in content, "The buggy direct multiplication by covariance is still present."


def test_generate_proposal_has_requested_covariance():
    """Compile and exercise the submitted generate_proposal implementation."""
    harness = r'''
#define main submitted_mcmc_main
#include "/home/user/mcmc_sequence.cpp"
#undef main
#include <cmath>
#include <iostream>

int main() {
    Matrix3d covariance;
    // This is L*L^T for L = [[1,0,0],[0.4,1.3,0],[-0.2,0.5,0.8]].
    covariance << 1.0, 0.4, -0.2,
                  0.4, 1.85, 0.57,
                 -0.2, 0.57, 0.93;

    const int n = 80000;
    mt19937 gen(918273);
    Vector3d current(0.75, -1.25, 2.0);
    double sums[3] = {0.0, 0.0, 0.0};
    double products[3][3] = {{0.0, 0.0, 0.0},
                             {0.0, 0.0, 0.0},
                             {0.0, 0.0, 0.0}};

    for (int k = 0; k < n; ++k) {
        Vector3d delta = generate_proposal(current, covariance, gen) - current;
        for (int i = 0; i < 3; ++i) {
            if (!std::isfinite(delta(i))) return 2;
            sums[i] += delta(i);
            for (int j = 0; j < 3; ++j)
                products[i][j] += delta(i) * delta(j);
        }
    }

    double expected[3][3] = {{1.0, 0.4, -0.2},
                              {0.4, 1.85, 0.57},
                              {-0.2, 0.57, 0.93}};
    for (int i = 0; i < 3; ++i) {
        double mean_i = sums[i] / n;
        if (std::fabs(mean_i) > 0.03) {
            std::cerr << "proposal increment mean is not zero at index " << i << std::endl;
            return 3;
        }
        for (int j = 0; j < 3; ++j) {
            double mean_j = sums[j] / n;
            double sample_cov = products[i][j] / n - mean_i * mean_j;
            if (std::fabs(sample_cov - expected[i][j]) > 0.06) {
                std::cerr << "proposal covariance mismatch at " << i << "," << j
                          << ": got " << sample_cov << ", expected " << expected[i][j]
                          << std::endl;
                return 4;
            }
        }
    }
    return 0;
}
'''
    harness_file = "/tmp/test_generate_proposal.cpp"
    harness_exe = "/tmp/test_generate_proposal"
    with open(harness_file, "w") as f:
        f.write(harness)

    compiled = subprocess.run(
        ["g++", "-std=c++11", "-O2", "-I", EIGEN_DIR, harness_file, "-o", harness_exe],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, f"Could not compile generate_proposal test harness:\n{compiled.stderr}"

    exercised = subprocess.run(
        [harness_exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert exercised.returncode == 0, (
        "generate_proposal does not produce increments with the requested covariance; "
        f"it may not be using the Cholesky factor.\n{exercised.stderr}"
    )


def test_executable_exists():
    """Test that the compiled binary exists, is executable, and is an ELF binary."""
    assert os.path.isfile(EXE_FILE), f"Executable {EXE_FILE} does not exist. Did you compile the code?"
    assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."
    with open(EXE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXE_FILE} is not a compiled ELF executable."


def test_posterior_mean():
    """Run the submitted binary and verify that it creates the correct CSV."""
    rebuilt_exe = "/tmp/mcmc_sequence_rebuilt"
    compiled = subprocess.run(
        ["g++", "-std=c++11", "-I", EIGEN_DIR, "-O3", CPP_FILE, "-o", rebuilt_exe],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, f"The submitted source does not compile with the required command:\n{compiled.stderr}"

    if os.path.exists(CSV_FILE):
        os.remove(CSV_FILE)
    rebuilt = subprocess.run(
        [rebuilt_exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert rebuilt.returncode == 0, f"Verifier rebuild failed when run:\n{rebuilt.stderr}"
    assert os.path.isfile(CSV_FILE), "The program rebuilt from the submitted source did not create posterior_mean.csv."
    with open(CSV_FILE, "r") as f:
        rebuilt_content = f.read().strip()

    os.remove(CSV_FILE)
    submitted = subprocess.run(
        [EXE_FILE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert submitted.returncode == 0, f"The submitted executable failed when run:\n{submitted.stderr}"
    assert os.path.isfile(CSV_FILE), f"File {CSV_FILE} does not exist. Did you run the compiled binary?"

    with open(CSV_FILE, "r") as f:
        content = f.read().strip()

    assert content == rebuilt_content, "The submitted executable's output does not match the submitted C++ source."

    parts = content.split(',')
    assert len(parts) == 3, f"Expected exactly 3 comma-separated values in CSV, got {len(parts)}."

    try:
        vals = [float(p) for p in parts]
    except ValueError:
        pytest.fail(f"CSV contains non-float values: {content}")

    assert all(math.isfinite(v) for v in vals), f"CSV contains non-finite values: {content}"
    expected = [2.5, -1.0, 3.1]
    for i, (val, exp) in enumerate(zip(vals, expected)):
        assert abs(val - exp) < 0.05, f"Value at index {i} ({val}) is not within 0.05 of expected ({exp}). The sampler may still be diverging."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
