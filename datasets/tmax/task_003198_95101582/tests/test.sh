#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import time

import pytest

ROOT = "/home/user/ml_prep"
SOURCE = os.path.join(ROOT, "tune_ridge.cpp")
PIPELINE = os.path.join(ROOT, "run_pipeline.sh")
RESULTS = os.path.join(ROOT, "tuning_results.txt")
EIGEN = os.path.join(ROOT, "eigen")


def expected_result():
    lambdas = [0.0, 10.0, 100.0, 1000.0]
    averages = []
    for lam in lambdas:
        fold_mses = []
        for fold in range(5):
            lo, hi = fold * 20, (fold + 1) * 20
            train = [i for i in range(100) if not (lo <= i < hi)]
            valid = list(range(lo, hi))

            n = float(len(train))
            sx = sum(float(i) for i in train)
            sxx = sum(float(i * i) for i in train)
            sy = sum(2.5 * i + 10.0 for i in train)
            sxy = sum(i * (2.5 * i + 10.0) for i in train)

            # Solve the required 2x2 ridge normal equation independently.
            a, b, d = n + lam, sx, sxx + lam
            det = a * d - b * b
            beta0 = (d * sy - b * sxy) / det
            beta1 = (a * sxy - b * sy) / det
            mse = sum((beta0 + beta1 * i - (2.5 * i + 10.0)) ** 2 for i in valid) / len(valid)
            fold_mses.append(mse)
        averages.append(sum(fold_mses) / 5.0)

    best_index = min(range(len(lambdas)), key=lambda i: averages[i])
    return lambdas[best_index], averages[best_index]


def read_and_validate_results():
    assert os.path.isfile(RESULTS), f"The results file {RESULTS} was not generated."
    with open(RESULTS, "r", encoding="utf-8") as f:
        content = f.read().strip()
    match = re.fullmatch(
        r"Best lambda: ([+-]?(?:\d+(?:\.\d*)?|\.\d+))\nBest MSE: ([+-]?(?:\d+\.\d{4}))",
        content,
    )
    assert match, "tuning_results.txt must contain exactly the two required, correctly formatted lines."
    expected_lambda, expected_mse = expected_result()
    assert float(match.group(1)) == expected_lambda
    assert match.group(2) == f"{expected_mse:.4f}"
    return content


@pytest.fixture(scope="session", autouse=True)
def execute_and_audit_artifacts():
    assert os.path.isdir(ROOT)
    assert os.path.isfile(SOURCE)
    assert os.path.isfile(PIPELINE)

    # A real Eigen installation must support ordinary matrix operations and expose
    # the requested 3.4.0 version, rather than merely providing a placeholder file.
    probe_dir = tempfile.mkdtemp(prefix="eigen_probe_")
    try:
        probe_cpp = os.path.join(probe_dir, "probe.cpp")
        probe_bin = os.path.join(probe_dir, "probe")
        with open(probe_cpp, "w", encoding="utf-8") as f:
            f.write(r'''#include <Eigen/Dense>
#if EIGEN_WORLD_VERSION != 3 || EIGEN_MAJOR_VERSION != 4 || EIGEN_MINOR_VERSION != 0
#error Wrong Eigen version
#endif
#include <cmath>
int main() {
    Eigen::Matrix2d a;
    a << 4.0, 1.0, 1.0, 3.0;
    Eigen::Vector2d b;
    b << 1.0, 2.0;
    Eigen::Vector2d x = a.ldlt().solve(b);
    return ((a * x - b).norm() < 1e-10) ? 0 : 1;
}
''')
        subprocess.run(
            ["g++", "-std=c++17", "-I" + EIGEN, probe_cpp, "-o", probe_bin],
            check=True, timeout=60,
        )
        subprocess.run([probe_bin], check=True, timeout=10)
    finally:
        shutil.rmtree(probe_dir, ignore_errors=True)

    # Inspect the implementation for the required numerical machinery. This is
    # supplementary to compiling and executing it below.
    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    code = re.sub(r"/\*.*?\*/|//[^\n]*", " ", source_text, flags=re.S)
    assert re.search(r"#\s*include\s*[<\"][^>\"]*Eigen/", code), "The program must use the installed Eigen headers."
    assert "Eigen::" in code, "No Eigen implementation was found in tune_ridge.cpp."
    assert re.search(r"\btranspose\s*\(", code), "The ridge normal-equation implementation is missing transpose operations."
    for value in ("0", "10", "100", "1000"):
        assert re.search(rf"(?<![\w.]){value}(?:\.0*)?(?![\w.])", code), f"Lambda candidate {value} is missing."
    assert re.search(r"(?<![\w.])2\.5(?:0*)?(?![\w.])", code), "The required target slope is missing."

    # The submitted pipeline must itself compile and run successfully from a
    # clean result state.
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    started = time.time()
    subprocess.run(["bash", PIPELINE], cwd=ROOT, check=True, timeout=120)
    assert os.path.getmtime(RESULTS) >= started - 1.0
    read_and_validate_results()

    # Compile the submitted source independently, then execute that binary after
    # deleting the result. This proves the C++ artifact, not a prewritten file,
    # generates the required answer.
    audit_dir = tempfile.mkdtemp(prefix="ridge_audit_")
    try:
        audit_bin = os.path.join(audit_dir, "tune_ridge")
        subprocess.run(
            ["g++", "-std=c++17", "-O2", "-I" + EIGEN, SOURCE, "-o", audit_bin],
            cwd=ROOT, check=True, timeout=120,
        )
        os.remove(RESULTS)
        subprocess.run([audit_bin], cwd=ROOT, check=True, timeout=30)
        read_and_validate_results()
    finally:
        shutil.rmtree(audit_dir, ignore_errors=True)

    # Verify run_pipeline.sh really recompiles tune_ridge.cpp instead of merely
    # writing the expected text or running a stale executable.
    with open(SOURCE, "rb") as f:
        original_source = f.read()
    source_mode = os.stat(SOURCE).st_mode
    try:
        with open(SOURCE, "ab") as f:
            f.write(b"\n#error verifier_forced_compile_failure\n")
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        bad = subprocess.run(
            ["bash", PIPELINE], cwd=ROOT, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=120,
        )
        assert bad.returncode != 0, "run_pipeline.sh did not compile tune_ridge.cpp."
        assert not os.path.exists(RESULTS), "The pipeline produced results despite compilation failure."
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        os.chmod(SOURCE, source_mode)

    # Leave the requested final artifact in place using the restored submission.
    subprocess.run(["bash", PIPELINE], cwd=ROOT, check=True, timeout=120)
    read_and_validate_results()


def test_ml_prep_directory_exists():
    assert os.path.isdir("/home/user/ml_prep"), "The directory /home/user/ml_prep does not exist."


def test_eigen_extracted():
    eigen_path = "/home/user/ml_prep/eigen/Eigen"
    assert os.path.isdir(eigen_path), f"Eigen headers not found at {eigen_path}."
    assert os.path.isfile(os.path.join(eigen_path, "Dense")), "Eigen/Dense header not found, extraction might be incorrect."


def test_cpp_file_exists():
    assert os.path.isfile("/home/user/ml_prep/tune_ridge.cpp"), "The C++ source file tune_ridge.cpp is missing."


def test_run_pipeline_script_exists():
    script_path = "/home/user/ml_prep/run_pipeline.sh"
    assert os.path.isfile(script_path), f"The bash script {script_path} is missing."
    assert os.access(script_path, os.X_OK) or True, "The run_pipeline.sh script should ideally be executable."


def test_tuning_results_file():
    results_file = "/home/user/ml_prep/tuning_results.txt"
    assert os.path.isfile(results_file), f"The results file {results_file} was not generated."

    with open(results_file, "r") as f:
        content = f.read().strip()

    # Check for Best lambda
    assert re.search(r"Best lambda:\s*0", content), "The best lambda should be 0."

    # Check for Best MSE
    assert re.search(r"Best MSE:\s*0\.0000", content), "The best MSE should be 0.0000."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
