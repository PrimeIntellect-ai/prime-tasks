#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import subprocess
import tempfile
import numpy as np

PREDICTOR = "/home/user/predictor"
SOURCE = "/home/user/predictor.cpp"
CV_LOG = "/home/user/cv_results.log"
ORACLE = "/app/oracle"


def test_predictor_exists():
    path = PREDICTOR
    assert os.path.exists(path), f"Missing predictor executable at {path}"
    assert os.path.isfile(path), f"{path} is not a file"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def test_predictor_source_exists_and_implements_ridge_cv():
    assert os.path.exists(SOURCE), f"Missing predictor source at {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty"

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    no_comments = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    no_comments = re.sub(r"//[^\n]*", " ", no_comments)
    includes = re.findall(r"^\s*#\s*include\s*[<\"]([^>\"]+)[>\"]", no_comments, flags=re.M)
    assert any("Eigen" in header for header in includes), \
        "predictor.cpp must use Eigen for the Ridge Regression math"

    code = re.sub(r'"(?:\\.|[^"\\])*"', ' ', no_comments)
    code = re.sub(r"'(?:\\.|[^'\\])*'", ' ', code)
    assert re.search(r"\b(MatrixXd|VectorXd|Eigen\s*::\s*Matrix|Eigen\s*::\s*Vector)\b", code), \
        "predictor.cpp does not contain Eigen matrix/vector Ridge Regression code"
    assert re.search(r"\b(lambda|l2|regularization|penalty)\b", code, flags=re.I), \
        "predictor.cpp does not contain an L2 regularization parameter"
    assert re.search(r"\b(fold|folds|kfold|cross_validation|crossValidation)\b", code, flags=re.I), \
        "predictor.cpp does not contain k-fold cross-validation logic"
    assert re.search(r"\b(ldlt|llt|solve|inverse|colPivHouseholderQr|householderQr)\b", code), \
        "predictor.cpp does not solve a Ridge Regression linear system"
    assert re.search(r"\b(Identity|diagonal|setIdentity)\b", code) or re.search(
        r"\([^\n;]*,[^\n;]*\)\s*\+=\s*\w*(lambda|l2|penalty)", code, flags=re.I
    ), "predictor.cpp does not appear to add an L2 penalty to the regression system"


def test_cv_results_log_exists():
    path = CV_LOG
    assert os.path.exists(path), f"Missing cv_results.log at {path}"
    assert os.path.isfile(path), f"{path} is not a file"


def test_cv_results_log_format_and_values():
    with open(CV_LOG, "r", encoding="utf-8", errors="strict") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 2, "cv_results.log must contain results for at least two lambda candidates"
    lambdas = []
    for line_number, line in enumerate(lines, 1):
        fields = [field.strip() for field in line.split(",")]
        assert len(fields) == 2, \
            f"cv_results.log line {line_number} must have format lambda, mean_validation_mse"
        try:
            lam = float(fields[0])
            mse = float(fields[1])
        except ValueError:
            assert False, f"cv_results.log line {line_number} contains non-numeric data"
        assert math.isfinite(lam) and lam >= 0, \
            f"Invalid lambda on cv_results.log line {line_number}"
        assert math.isfinite(mse) and mse >= 0, \
            f"Invalid validation MSE on cv_results.log line {line_number}"
        lambdas.append(lam)

    assert len(set(lambdas)) >= 2, "cv_results.log must evaluate at least two distinct lambdas"


def run_and_read(executable, csv_path, output_path, timeout=30):
    with open(output_path, "w") as f:
        subprocess.run([executable, csv_path], stdout=f, stderr=subprocess.PIPE,
                       check=True, timeout=timeout)
    try:
        values = np.loadtxt(output_path)
    except Exception as e:
        assert False, f"Failed to read output from {executable}; expected one float per line: {e}"
    return np.atleast_1d(values).astype(float)


def test_predictor_mse():
    # Compile the submitted source independently so the tested executable must be
    # reproducible from predictor.cpp rather than being an unrelated artifact.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "predictor_from_source")
        try:
            subprocess.run(
                ["g++", "-O2", "-std=c++17", "-I/usr/include/eigen3", SOURCE, "-o", rebuilt],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=60
            )
        except subprocess.CalledProcessError as e:
            assert False, f"predictor.cpp failed to compile: {e.stderr.decode(errors='replace')}"
        except subprocess.TimeoutExpired:
            assert False, "Compiling predictor.cpp timed out"

        # Use fresh, non-fixed samples on every verification run while retaining
        # the original 10,000-row, [-10, 10] evaluation domain.
        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
        sizes = (137, 997, 8866)
        for case, rows in enumerate(sizes):
            X = rng.uniform(-10, 10, size=(rows, 5))
            test_csv = os.path.join(tmpdir, f"hidden_test_{case}.csv")
            np.savetxt(test_csv, X, delimiter=",", fmt="%.9f")

            oracle_out = os.path.join(tmpdir, f"oracle_{case}.txt")
            expected = run_and_read(ORACLE, test_csv, oracle_out)
            assert len(expected) == len(X), "Oracle output length mismatch"

            for executable, label in ((PREDICTOR, "submitted predictor"),
                                      (rebuilt, "predictor rebuilt from predictor.cpp")):
                output = os.path.join(tmpdir, f"prediction_{case}_{os.path.basename(executable)}.txt")
                try:
                    predicted = run_and_read(executable, test_csv, output)
                except subprocess.CalledProcessError as e:
                    assert False, f"{label} failed to run: {e}"
                except subprocess.TimeoutExpired:
                    assert False, f"{label} timed out"

                assert len(predicted) == len(X), \
                    f"{label} output length mismatch: expected {len(X)}, got {len(predicted)}"
                assert np.all(np.isfinite(predicted)), f"{label} produced non-finite predictions"
                mse = np.mean((expected - predicted) ** 2)
                assert mse < 0.01, \
                    f"{label} MSE is too high: {mse:.6f} >= 0.01"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
