#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hook
cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import os
import numpy as np

_log_path = os.environ.get("VERIFY_LINALG_LOG")
_corrupt = os.environ.get("VERIFY_CORRUPT_DECOMP") == "1"

def _log(name):
    if _log_path:
        with open(_log_path, "a") as f:
            f.write(name + "\n")

_orig_svd = np.linalg.svd
_orig_eig = np.linalg.eig
_orig_eigh = np.linalg.eigh

def _svd(*args, **kwargs):
    _log("svd")
    u, s, vh = _orig_svd(*args, **kwargs)
    if _corrupt:
        vh = np.eye(vh.shape[0], vh.shape[1], dtype=vh.dtype)
    return u, s, vh

def _eig(*args, **kwargs):
    _log("eig")
    w, v = _orig_eig(*args, **kwargs)
    if _corrupt:
        v = np.eye(v.shape[0], v.shape[1], dtype=v.dtype)
    return w, v

def _eigh(*args, **kwargs):
    _log("eigh")
    w, v = _orig_eigh(*args, **kwargs)
    if _corrupt:
        v = np.eye(v.shape[0], v.shape[1], dtype=v.dtype)
    return w, v

np.linalg.svd = _svd
np.linalg.eig = _eig
np.linalg.eigh = _eigh
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import numpy as np

BASE = "/home/user/motif_analysis"
SCRIPT = os.path.join(BASE, "run_pipeline.sh")
MATRIX = os.path.join(BASE, "transition_matrix.csv")
OUTPUT = os.path.join(BASE, "steady_state.csv")
LOG = "/tmp/linalg_calls.log"


def run_pipeline(corrupt=False):
    if os.path.exists(LOG):
        os.remove(LOG)
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_hook" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    env["VERIFY_LINALG_LOG"] = LOG
    if corrupt:
        env["VERIFY_CORRUPT_DECOMP"] = "1"
    else:
        env.pop("VERIFY_CORRUPT_DECOMP", None)
    result = subprocess.run(
        [SCRIPT], capture_output=True, text=True, cwd=BASE, env=env
    )
    calls = ""
    if os.path.isfile(LOG):
        with open(LOG) as f:
            calls = f.read()
    return result, calls


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert len(content.splitlines()) == 1, "Output must be a single line."
    try:
        values = [float(x.strip()) for x in content.split(',')]
    except ValueError:
        raise AssertionError("Output file does not contain valid comma-separated floats.")
    assert len(values) == 10, f"Expected exactly 10 values, but got {len(values)}."
    values = np.asarray(values, dtype=float)
    assert np.all(np.isfinite(values)), "Output contains non-finite values."
    return values


def assert_decomposition_used(calls):
    observed = set(calls.splitlines())
    assert observed.intersection({"svd", "eig", "eigh"}), (
        "The pipeline did not execute an SVD or eigendecomposition."
    )


def expected_stationary(P):
    vals, vecs = np.linalg.eig(P.T)
    idx = int(np.argmin(np.abs(vals - 1.0)))
    v = np.real(vecs[:, idx])
    if v.sum() < 0:
        v = -v
    v = v / v.sum()
    return v


def check_general_output(P, values):
    total_sum = float(values.sum())
    assert abs(total_sum - 1.0) < 1e-5, f"Probabilities must sum to 1, but sum is {total_sum}."
    for i, val in enumerate(values):
        assert val >= -1e-7, f"Probabilities must be non-negative, but got {val} at index {i}."
    residual = np.linalg.norm(P.T @ values - values, 2)
    assert residual < 1e-6, f"Residual must be below 1e-6, but was {residual}."
    expected = expected_stationary(P)
    assert np.linalg.norm(values - expected, 2) < 2e-5, (
        "Output is not the steady-state distribution derived from the supplied matrix."
    )


def test_complete_pipeline():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(MATRIX, "rb") as f:
        original_bytes = f.read()

    try:
        # Preserve all checks against the originally supplied absorbing-state matrix.
        original = np.loadtxt(MATRIX, delimiter=",")
        result, calls = run_pipeline()
        assert result.returncode == 0, f"Pipeline script failed to execute. STDERR: {result.stderr}"
        assert_decomposition_used(calls)
        values = read_output()
        total_sum = float(values.sum())
        assert abs(total_sum - 1.0) < 1e-5, f"Probabilities must sum to 1, but sum is {total_sum}."
        assert abs(values[5] - 1.0) < 1e-5, f"State 5 must be approximately 1.0, but got {values[5]}."
        for i, val in enumerate(values):
            assert val >= -1e-7, f"Probabilities must be non-negative, but got {val} at index {i}."
        assert np.linalg.norm(original.T @ values - values, 2) < 1e-6

        # Confirm that the submitted workflow contains an explicit 2-norm-style
        # residual calculation and a tolerance no weaker than 1e-6.
        source_parts = []
        for name in os.listdir(BASE):
            path = os.path.join(BASE, name)
            if name == "run_pipeline.sh" or (name.endswith(".py") and os.path.isfile(path)):
                with open(path, "r", errors="ignore") as f:
                    source_parts.append(f.read())
        source = "\n".join(source_parts)
        lower = source.lower()
        numeric_literals = re.findall(r"(?<![\w.])(?:\d+\.\d*|\.\d+|\d+)(?:e[+-]?\d+)?", lower)
        has_tolerance = any(0.0 < float(x) <= 1e-6 for x in numeric_literals)
        has_tolerance = has_tolerance or bool(re.search(r"10\s*\*\*\s*-\s*(?:[6-9]|[1-9]\d+)", lower))
        assert has_tolerance, "No analytical validation threshold of 1e-6 or stricter was found."
        assert ("norm" in lower or "sqrt" in lower) and (
            "@" in source or "matmul" in lower or "dot" in lower
        ), "No explicit residual norm calculation was found in the pipeline workflow."

        # Exercise matrices whose stationary distributions are not the fixed
        # absorbing-state answer. Expected answers are derived by the verifier.
        rng = np.random.default_rng(20260911)
        challenges = []
        for offset in (0.15, 0.7):
            P = rng.random((10, 10)) + offset
            P /= P.sum(axis=1, keepdims=True)
            challenges.append(P)

        for P in challenges:
            np.savetxt(MATRIX, P, delimiter=",", fmt="%.12g")
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            result, calls = run_pipeline()
            assert result.returncode == 0, f"Pipeline failed on a valid transition matrix. STDERR: {result.stderr}"
            assert_decomposition_used(calls)
            check_general_output(P, read_output())

        # Corrupt the decomposition's vectors while retaining valid shapes. A
        # pipeline that really validates its computed residual must reject this.
        P = challenges[0]
        np.savetxt(MATRIX, P, delimiter=",", fmt="%.12g")
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result, calls = run_pipeline(corrupt=True)
        assert_decomposition_used(calls)
        assert result.returncode != 0, (
            "Pipeline accepted a deliberately invalid decomposition; its required "
            "analytical residual validation is missing or ineffective."
        )
    finally:
        with open(MATRIX, "wb") as f:
            f.write(original_bytes)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
