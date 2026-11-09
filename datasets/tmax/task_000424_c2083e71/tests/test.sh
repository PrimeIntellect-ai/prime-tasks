#!/bin/bash
set -e
mkdir -p /logs/verifier

AUDIT_DIR=/tmp/verifier_audit
rm -rf "$AUDIT_DIR"
mkdir -p "$AUDIT_DIR"

cat << 'AUDIT_EOF' > "$AUDIT_DIR/sitecustomize.py"
import os
import multiprocessing.pool as _mp_pool

_log_path = os.environ.get("VERIFIER_MP_LOG")
_original_init = _mp_pool.Pool.__init__

def _write(message):
    if _log_path:
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(message + "\n")

def _audited_init(self, *args, **kwargs):
    result = _original_init(self, *args, **kwargs)
    _write("P:" + str(getattr(self, "_processes", None)))
    return result

_mp_pool.Pool.__init__ = _audited_init

for _name in ("map", "map_async", "starmap", "starmap_async", "imap",
              "imap_unordered", "apply", "apply_async"):
    if hasattr(_mp_pool.Pool, _name):
        _original = getattr(_mp_pool.Pool, _name)
        def _make_wrapper(name, original):
            def _wrapper(self, *args, **kwargs):
                _write("D:" + name)
                return original(self, *args, **kwargs)
            return _wrapper
        setattr(_mp_pool.Pool, _name, _make_wrapper(_name, _original))
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import os
import re
import subprocess
import sys

import numpy as np
from scipy.fft import rfft
from scipy.signal.windows import hamming
from scipy.sparse.csgraph import minimum_spanning_tree
from scipy.stats import wasserstein_distance

SIGNALS = "/home/user/signals.csv"
RESULT = "/home/user/result.txt"
SCRIPT = "/home/user/analyze.py"
AUDIT_DIR = "/tmp/verifier_audit"
AUDIT_LOG = "/tmp/verifier_mp.log"

_original_signals = open(SIGNALS, "rb").read() if os.path.isfile(SIGNALS) else None
_original_result = open(RESULT, "rb").read() if os.path.isfile(RESULT) else None

@atexit.register
def restore_files():
    if _original_signals is not None:
        with open(SIGNALS, "wb") as f:
            f.write(_original_signals)
    if _original_result is not None:
        with open(RESULT, "wb") as f:
            f.write(_original_result)
    elif os.path.exists(RESULT):
        os.remove(RESULT)


def test_result_file_exists():
    file_path = RESULT
    assert os.path.exists(file_path), f"File {file_path} is missing. Did your script create it?"
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_result_content():
    file_path = RESULT
    assert os.path.exists(file_path), f"File {file_path} is missing."
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_value = "0.5898"
    assert content == expected_value, (
        f"Expected the result to be '{expected_value}', but found '{content}'."
    )


def test_analyze_script_exists():
    file_path = SCRIPT
    assert os.path.exists(file_path), f"File {file_path} is missing. You must write your code in this file."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def reference_result(path):
    data = np.loadtxt(path, delimiter=",")
    assert data.shape == (10, 1024)
    window = hamming(1024)
    dominant = []
    for row in data:
        magnitude = np.abs(rfft(row * window))
        magnitude[0] = 0
        dominant.append(int(np.argmax(magnitude)))
    b = np.asarray(dominant, dtype=float)

    weights = np.abs(b[:, None] - b[None, :])
    tree = minimum_spanning_tree(weights).toarray()
    adjacency = tree + tree.T
    laplacian = np.diag(adjacency.sum(axis=1)) - adjacency
    x = np.linalg.solve(laplacian + np.eye(len(b)), b)
    return f"{wasserstein_distance(b, x):.4f}"


def run_submission(data):
    np.savetxt(SIGNALS, data, delimiter=",", fmt="%.18e")
    if os.path.exists(RESULT):
        os.remove(RESULT)
    if os.path.exists(AUDIT_LOG):
        os.remove(AUDIT_LOG)

    expected = reference_result(SIGNALS)
    env = os.environ.copy()
    env["VERIFIER_MP_LOG"] = AUDIT_LOG
    env["PYTHONPATH"] = AUDIT_DIR + os.pathsep + env.get("PYTHONPATH", "")
    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert completed.returncode == 0, (
        "analyze.py did not run successfully.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULT), "analyze.py did not create /home/user/result.txt"
    with open(RESULT, "r", encoding="utf-8") as f:
        actual = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{4}", actual), (
        f"Result must be written with exactly four decimal places, found {actual!r}"
    )
    assert actual == expected, f"Expected {expected} for the supplied signals, found {actual}"

    assert os.path.isfile(AUDIT_LOG), "analyze.py did not create a multiprocessing Pool"
    with open(AUDIT_LOG, "r", encoding="utf-8") as f:
        events = [line.strip() for line in f if line.strip()]
    assert "P:4" in events, "analyze.py must use a multiprocessing Pool with 4 workers"
    assert any(event.startswith("D:") for event in events), (
        "The multiprocessing Pool was created but no work was dispatched through it"
    )
    return actual


def canonical_data():
    np.random.seed(42)
    rows = []
    for _ in range(10):
        t = np.linspace(0, 1, 1024)
        freq = np.random.randint(10, 100)
        noise = np.random.normal(0, 0.5, 1024)
        rows.append(np.sin(2 * np.pi * freq * t) + noise)
    return np.asarray(rows)


def randomized_data(rng):
    n = 1024
    t = np.arange(n) / n
    frequencies = rng.choice(np.arange(7, 230), size=10, replace=False)
    rows = []
    for freq in frequencies:
        phase = rng.uniform(0, 2 * np.pi)
        amplitude = rng.uniform(0.8, 1.7)
        noise = rng.normal(0, 0.03, n)
        rows.append(amplitude * np.sin(2 * np.pi * freq * t + phase) + noise)
    return np.asarray(rows)


def test_script_executes_full_pipeline():
    canonical = canonical_data()
    assert reference_result_from_array(canonical) == "0.5898"
    assert run_submission(canonical) == "0.5898"

    rng = np.random.default_rng()
    run_submission(randomized_data(rng))
    run_submission(randomized_data(rng))


def reference_result_from_array(data):
    np.savetxt(SIGNALS, data, delimiter=",", fmt="%.18e")
    return reference_result(SIGNALS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
