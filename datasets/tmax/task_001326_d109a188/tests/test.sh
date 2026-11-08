#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/run_student_restricted.py
import ctypes
import errno
import platform
import runpy
import sys

# Prevent the submitted Python program (and its children) from executing the
# shipped legacy binary or any copied/renamed executable. Correct NumPy-based
# implementations do not need execve after the interpreter has started.
class SockFilter(ctypes.Structure):
    _fields_ = [
        ("code", ctypes.c_ushort),
        ("jt", ctypes.c_ubyte),
        ("jf", ctypes.c_ubyte),
        ("k", ctypes.c_uint),
    ]

class SockFprog(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_ushort),
        ("filter", ctypes.POINTER(SockFilter)),
    ]

machine = platform.machine().lower()
if machine in ("x86_64", "amd64"):
    execve_nr, execveat_nr = 59, 322
elif machine in ("aarch64", "arm64"):
    execve_nr, execveat_nr = 221, 281
else:
    raise RuntimeError(f"Unsupported verification architecture: {machine}")

BPF_LD = 0x00
BPF_W = 0x00
BPF_ABS = 0x20
BPF_JMP = 0x05
BPF_JEQ = 0x10
BPF_K = 0x00
BPF_RET = 0x06
SECCOMP_RET_ALLOW = 0x7fff0000
SECCOMP_RET_ERRNO = 0x00050000
PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2

rules = (SockFilter * 6)(
    SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, execve_nr),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, execveat_nr),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(rules), rules)
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(program)) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script, input_csv, output_csv = sys.argv[1:4]
sys.argv = [script, input_csv, output_csv]
runpy.run_path(script, run_name="__main__")
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys
import tempfile

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/process_spectra.py"
LEGACY_PATH = "/app/legacy_cleaner"
STATS_PATH = "/home/user/stats.json"
RUNNER_PATH = "/tmp/run_student_restricted.py"


def test_process_spectra_exists():
    """Check that the requested artifact exists and is a Python source file."""
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path is not a file: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "rb") as f:
        submitted = f.read()
    assert not submitted.startswith(b"\x7fELF"), "process_spectra.py is an executable, not a Python script"
    if os.path.exists(LEGACY_PATH):
        with open(LEGACY_PATH, "rb") as f:
            assert submitted != f.read(), "Submitted artifact is the legacy executable"


def reference_process(data):
    transformed = np.fft.fft(data, axis=1)
    transformed[:, 32:993] = 0
    smoothed = np.fft.ifft(transformed, axis=1).real
    left_anchor = np.mean(smoothed[:, :10], axis=1)
    right_anchor = np.mean(smoothed[:, 1014:], axis=1)
    position = np.linspace(0.0, 1.0, 1024)
    baseline = left_anchor[:, None] + (right_anchor - left_anchor)[:, None] * position
    return smoothed - baseline


def test_pipeline_accuracy_and_stats():
    """Run the submitted pipeline on fresh data and validate output and bootstrap CI."""
    rng = np.random.default_rng(secrets.randbits(128))
    n_rows = 1000
    n_cols = 1024
    x = np.linspace(0, 4 * np.pi, n_cols)
    phase = rng.uniform(0, 2 * np.pi, size=(n_rows, 1))
    amplitude = rng.uniform(1.0, 2.0, size=(n_rows, 1))
    signal = np.sin(x[None, :] + phase) * amplitude
    noise = rng.normal(0, 0.5, size=(n_rows, n_cols))
    starts = rng.uniform(0, 1, size=(n_rows, 1))
    ends = rng.uniform(0, 5, size=(n_rows, 1))
    trend = starts + (ends - starts) * np.linspace(0, 1, n_cols)
    data = signal + noise + trend
    oracle_data = reference_process(data)

    with tempfile.TemporaryDirectory(prefix="spectra_verify_") as workdir:
        hidden_in = os.path.join(workdir, "input.csv")
        hidden_out = os.path.join(workdir, "output.csv")
        np.savetxt(hidden_in, data, delimiter=",")

        for path in (hidden_out, STATS_PATH):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        result = subprocess.run(
            [sys.executable, RUNNER_PATH, SCRIPT_PATH, hidden_in, hidden_out],
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"Student script failed:\n{result.stderr}"
        assert os.path.exists(hidden_out), "Student script did not create the output file."

        agent_data = np.loadtxt(hidden_out, delimiter=",")
        assert agent_data.shape == oracle_data.shape, (
            f"Shape mismatch: agent {agent_data.shape} vs oracle {oracle_data.shape}"
        )
        assert np.all(np.isfinite(agent_data)), "Output contains non-finite values"
        mse = np.mean((agent_data - oracle_data) ** 2)
        assert mse <= 1e-4, f"MSE too high: {mse} (threshold is 1e-4)"

    assert os.path.exists(STATS_PATH), f"Missing stats file: {STATS_PATH}"
    try:
        with open(STATS_PATH, "r") as f:
            stats = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Invalid JSON in {STATS_PATH}")

    assert "ci_lower" in stats, "Missing 'ci_lower' in stats.json"
    assert "ci_upper" in stats, "Missing 'ci_upper' in stats.json"
    ci_lower = float(stats["ci_lower"])
    ci_upper = float(stats["ci_upper"])
    assert np.isfinite(ci_lower) and np.isfinite(ci_upper), "CI endpoints must be finite"
    assert ci_lower < ci_upper, f"ci_lower ({ci_lower}) must be less than ci_upper ({ci_upper})"

    # Recompute the requested percentile bootstrap CI of the mean maximum peak
    # height. A small tolerance permits normal Monte Carlo variation between
    # independent, valid 1000-resample implementations.
    max_vals = np.max(oracle_data, axis=1)
    bootstrap_rng = np.random.default_rng(947231)
    samples = bootstrap_rng.choice(max_vals, size=(1000, len(max_vals)), replace=True)
    expected_lower, expected_upper = np.percentile(np.mean(samples, axis=1), [2.5, 97.5])
    expected_width = expected_upper - expected_lower
    tolerance = max(1e-4, 0.25 * expected_width)
    assert abs(ci_lower - expected_lower) <= tolerance, (
        f"ci_lower {ci_lower} does not match the recomputed percentile bootstrap CI "
        f"({expected_lower}, tolerance {tolerance})"
    )
    assert abs(ci_upper - expected_upper) <= tolerance, (
        f"ci_upper {ci_upper} does not match the recomputed percentile bootstrap CI "
        f"({expected_upper}, tolerance {tolerance})"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
