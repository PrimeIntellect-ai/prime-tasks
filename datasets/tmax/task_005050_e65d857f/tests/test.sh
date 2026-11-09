#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import h5py
import numpy as np
import pytest
import scipy.stats

RUN_SCRIPT = "/home/user/run_analysis.sh"
ANALYZE_SCRIPT = "/home/user/analyze.py"
DATA_FILE = "/home/user/data.h5"
OUTPUT_FILE = "/home/user/hypothesis_test.txt"
MARKER_FILE = "/tmp/verifier_analyze_marker"


def reference_probability(X, y):
    U, S, Vt = np.linalg.svd(X, full_matrices=False)
    S_inv = np.diag(1 / S)
    X_pinv = Vt.T @ S_inv @ U.T
    w_ols = X_pinv @ y

    def log_posterior(w):
        log_prior = np.sum(scipy.stats.norm.logpdf(w, 0, 1))
        log_lik = np.sum(scipy.stats.norm.logpdf(y, X @ w, 0.5))
        return log_prior + log_lik

    np.random.seed(42)
    w_current = w_ols.copy()
    lp_current = log_posterior(w_current)
    samples = []

    for _ in range(10000):
        w_prop = w_current + np.random.randn(10) * 0.05
        lp_prop = log_posterior(w_prop)
        if np.log(np.random.rand()) < lp_prop - lp_current:
            w_current = w_prop
            lp_current = lp_prop
        samples.append(w_current.copy())

    samples = np.asarray(samples)[2000:]
    return float(np.mean(samples[:, 0] > 1.0))


def read_data():
    with h5py.File(DATA_FILE, "r") as f:
        return f["X"][:], f["y"][:]


def write_data(X, y):
    with h5py.File(DATA_FILE, "w") as f:
        f.create_dataset("X", data=X)
        f.create_dataset("y", data=y)


def read_probability():
    assert os.path.exists(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."
    content = open(OUTPUT_FILE, "r").read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(
            f"The content of {OUTPUT_FILE} is not a valid floating-point number. Found: '{content}'"
        )
    assert np.isfinite(value), f"The calculated probability {value} is not finite."
    return value


def run_pipeline(expected):
    if os.path.lexists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    if os.path.lexists(MARKER_FILE):
        os.remove(MARKER_FILE)

    result = subprocess.run(
        [RUN_SCRIPT],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"{RUN_SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(MARKER_FILE), (
        f"{RUN_SCRIPT} did not execute {ANALYZE_SCRIPT}."
    )

    actual = read_probability()
    assert abs(actual - expected) < 0.02, (
        f"The calculated probability {actual} differs from the reference probability "
        f"{expected} by more than the allowed tolerance of 0.02."
    )


def test_scripts_exist_and_analysis_is_implemented():
    assert os.path.exists(RUN_SCRIPT), f"The script {RUN_SCRIPT} does not exist."
    assert os.path.isfile(RUN_SCRIPT), f"{RUN_SCRIPT} is not a file."
    assert os.access(RUN_SCRIPT, os.X_OK), f"The script {RUN_SCRIPT} is not executable."

    assert os.path.exists(ANALYZE_SCRIPT), f"The script {ANALYZE_SCRIPT} does not exist."
    assert os.path.isfile(ANALYZE_SCRIPT), f"{ANALYZE_SCRIPT} is not a file."

    source = open(ANALYZE_SCRIPT, "r").read()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"{ANALYZE_SCRIPT} is not valid Python: {exc}")

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(
        (isinstance(call.func, ast.Name) and call.func.id == "svd")
        or (isinstance(call.func, ast.Attribute) and call.func.attr == "svd")
        for call in calls
    ), "analyze.py does not compute an SVD."

    assert any(
        ((isinstance(call.func, ast.Name) and call.func.id == "seed")
         or (isinstance(call.func, ast.Attribute) and call.func.attr == "seed"))
        and call.args
        and isinstance(call.args[0], ast.Constant)
        and call.args[0].value == 42
        for call in calls
    ), "analyze.py does not set the NumPy random seed to 42."

    assert any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree)), (
        "analyze.py does not contain a custom sampling loop."
    )
    assert any(
        isinstance(node, ast.Constant) and node.value == 10000
        for node in ast.walk(tree)
    ), "analyze.py does not specify the required 10,000 MCMC iterations."


def test_pipeline_execution_and_results():
    original_analyze = open(ANALYZE_SCRIPT, "rb").read()
    original_analyze_mode = stat.S_IMODE(os.stat(ANALYZE_SCRIPT).st_mode)
    original_data = open(DATA_FILE, "rb").read()
    output_existed = os.path.isfile(OUTPUT_FILE)
    original_output = open(OUTPUT_FILE, "rb").read() if output_existed else None

    fd, saved_analyze = tempfile.mkstemp(prefix="submitted_analyze_", suffix=".py")
    os.close(fd)
    with open(saved_analyze, "wb") as f:
        f.write(original_analyze)

    wrapper = f'''#!/usr/bin/env python3
with open({MARKER_FILE!r}, "a") as _marker:
    _marker.write("executed\\n")
with open({saved_analyze!r}, "rb") as _source_file:
    _source = _source_file.read()
exec(compile(_source, {ANALYZE_SCRIPT!r}, "exec"), {{
    "__name__": "__main__",
    "__file__": {ANALYZE_SCRIPT!r},
    "__package__": None,
}})
'''

    try:
        with open(ANALYZE_SCRIPT, "w") as f:
            f.write(wrapper)
        os.chmod(ANALYZE_SCRIPT, original_analyze_mode | stat.S_IXUSR)

        # First exercise the pipeline on the researcher-provided dataset.
        X, y = read_data()
        run_pipeline(reference_probability(X, y))

        # Then use unpredictable valid datasets so a prewritten output cannot pass.
        rng = np.random.default_rng(secrets.randbits(128))
        for _ in range(2):
            X_test = rng.normal(size=(100, 10))
            weights = rng.normal(0, 0.35, size=10)
            weights[0] = rng.uniform(0.93, 1.08)
            y_test = X_test @ weights + rng.normal(0, 0.5, size=100)
            expected = reference_probability(X_test, y_test)
            write_data(X_test, y_test)
            run_pipeline(expected)
    finally:
        with open(ANALYZE_SCRIPT, "wb") as f:
            f.write(original_analyze)
        os.chmod(ANALYZE_SCRIPT, original_analyze_mode)
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)
        if output_existed:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
        elif os.path.lexists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        if os.path.lexists(MARKER_FILE):
            os.remove(MARKER_FILE)
        if os.path.exists(saved_analyze):
            os.remove(saved_analyze)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
