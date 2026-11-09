#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SOURCE = "/home/user/prepare_data.cpp"
RUN_SCRIPT = "/home/user/run.sh"
LOG = "/home/user/validation.log"


def expected_norm(n=2000, epsilon=1e-3):
    """Compute the expected norm independently from determinant ratios.

    The squared Cholesky diagonal entries are the successive determinant
    ratios of the leading principal minors. The first n-1 minors are path
    tridiagonal matrices; the final determinant is obtained from the known
    eigenvalues of the regularized cycle Laplacian.
    """
    a = 2.0 + epsilon
    ratio = a
    pivot_sum = 0.0
    log_path_det = 0.0

    for k in range(1, n):
        if k == 1:
            ratio = a
        else:
            ratio = a - 1.0 / ratio
        pivot_sum += ratio
        log_path_det += math.log(ratio)

    log_cycle_det = sum(
        math.log(a - 2.0 * math.cos(2.0 * math.pi * j / n))
        for j in range(n)
    )
    final_pivot = math.exp(log_cycle_det - log_path_det)
    return math.sqrt(pivot_sum + final_pivot)


def read_and_validate_log():
    assert os.path.isfile(LOG), f"{LOG} was not created."
    with open(LOG, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert re.fullmatch(r"[+-]?\d+\.\d{6}", content), (
        "validation.log must contain only one numeric value formatted to "
        f"6 decimal places. Got: {content!r}"
    )
    actual = float(content)
    expected = expected_norm()
    tolerance = 1e-4
    assert math.isfinite(actual) and abs(actual - expected) < tolerance, (
        f"The computed L2 norm is incorrect. Expected approximately "
        f"{expected:.6f}, but got {actual:.6f}."
    )


def test_files_exist():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(RUN_SCRIPT), f"{RUN_SCRIPT} does not exist."


def test_required_implementation_features_are_present():
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()
    with open(RUN_SCRIPT, "r", encoding="utf-8") as f:
        script = f.read()

    # Ignore comments when checking that required APIs/directives are used.
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)

    assert "Eigen::" in code, "prepare_data.cpp must use the Eigen library."
    assert re.search(r"(?:Eigen::)?LLT\s*<|\.llt\s*\(", code), (
        "prepare_data.cpp must use Eigen's Cholesky/LLT decomposition."
    )
    assert re.search(r"#\s*pragma\s+omp\b[^\n]*\bparallel\b", code), (
        "Dense Laplacian construction must be parallelized with OpenMP."
    )
    assert re.search(r"#\s*pragma\s+omp\b[^\n]*\bfor\b", code), (
        "An OpenMP work-sharing loop is required."
    )
    assert "-fopenmp" in script, "run.sh must compile with OpenMP enabled."
    assert re.search(r"3\.4\.0", script), "run.sh must obtain Eigen version 3.4.0."


def test_run_script_and_compiled_program():
    result = subprocess.run(
        ["bash", RUN_SCRIPT], cwd="/home/user", capture_output=True,
        text=True, timeout=300
    )
    assert result.returncode == 0, (
        f"run.sh failed to execute. stdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )
    read_and_validate_log()

    # Compile the submitted C++ artifact ourselves so run.sh cannot pass by
    # merely writing a precomputed value.
    eigen_headers = "/home/user/eigen/Eigen"
    assert os.path.isdir(eigen_headers), (
        "run.sh did not make Eigen headers available under /home/user/eigen."
    )
    binary = "/tmp/prepare_data_verified"
    compile_result = subprocess.run(
        ["g++", "-O3", "-fopenmp", "-std=c++17", "-I/home/user/eigen",
         SOURCE, "-o", binary],
        capture_output=True, text=True, timeout=180
    )
    assert compile_result.returncode == 0, (
        f"prepare_data.cpp failed independent compilation. "
        f"stderr: {compile_result.stderr}"
    )
    assert os.path.isfile(binary)
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiler output is not an ELF executable."

    if os.path.exists(LOG):
        os.remove(LOG)
    program_result = subprocess.run(
        [binary], cwd="/home/user", capture_output=True, text=True, timeout=300
    )
    assert program_result.returncode == 0, (
        f"The independently compiled program failed. "
        f"stderr: {program_result.stderr}"
    )
    read_and_validate_log()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
