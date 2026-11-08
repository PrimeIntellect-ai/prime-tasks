#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import stat
import subprocess
import tempfile

import numpy as np


def expected_features(f):
    """Independently compute the specified Forward Euler and FFT result."""
    dt = 0.01
    omega = 2.0 * math.pi * f
    y = 1.0
    velocity = 0.0
    values = []

    for _ in range(100):
        values.append(y)
        y, velocity = y + dt * velocity, velocity - dt * omega * omega * y

    times = np.arange(100, dtype=float) * dt
    numerical = np.asarray(values, dtype=float)
    exact = np.cos(omega * times)
    max_error = np.max(np.abs(numerical - exact))

    spectrum = np.fft.rfft(numerical)
    bins = np.fft.rfftfreq(100, d=dt)
    peak_freq = bins[np.argmax(np.abs(spectrum))]
    return f"{max_error:.4f},{peak_freq:.1f}"


def test_generate_features_behavior():
    """Execute the Python artifact on required and verifier-selected inputs."""
    py_script = "/home/user/generate_features.py"
    assert os.path.exists(py_script), f"Python script {py_script} does not exist."
    assert os.path.isfile(py_script), f"Python script {py_script} is not a regular file."

    frequencies = [1, 2, 3, 4, 5]
    frequencies.extend(secrets.SystemRandom().sample(range(6, 31), 4))

    for f in frequencies:
        result = subprocess.run(
            ["python3", py_script, str(f)],
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"generate_features.py failed for f={f}: {result.stderr}"
        )
        lines = result.stdout.splitlines()
        assert len(lines) == 1, (
            f"generate_features.py must print exactly one line for f={f}; "
            f"got {result.stdout!r}"
        )
        assert lines[0] == expected_features(f), (
            f"Incorrect Forward Euler/FFT result for f={f}: {lines[0]!r}"
        )


def test_build_script_executes_generator():
    """Run the Bash artifact from scratch and verify its five generator calls."""
    bash_script = "/home/user/build_dataset.sh"
    py_script = "/home/user/generate_features.py"
    csv_path = "/home/user/dataset.csv"

    assert os.path.exists(bash_script), f"Bash script {bash_script} does not exist."
    assert os.path.exists(py_script), f"Python script {py_script} does not exist."

    backup_fd, backup_path = tempfile.mkstemp(prefix="generate_features_backup_", suffix=".py")
    os.close(backup_fd)
    os.unlink(backup_path)
    log_fd, log_path = tempfile.mkstemp(prefix="generator_calls_", suffix=".jsonl")
    os.close(log_fd)

    os.replace(py_script, backup_path)
    wrapper = f'''#!/usr/bin/env python3
import json
import subprocess
import sys

with open({log_path!r}, "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
result = subprocess.run(
    [sys.executable, {backup_path!r}] + sys.argv[1:],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
raise SystemExit(result.returncode)
'''

    try:
        with open(py_script, "w") as f:
            f.write(wrapper)
        os.chmod(py_script, 0o755)
        if os.path.lexists(csv_path):
            os.remove(csv_path)

        result = subprocess.run(
            ["/bin/bash", bash_script],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=30,
        )
    finally:
        os.replace(backup_path, py_script)

    assert result.returncode == 0, f"build_dataset.sh failed: {result.stderr}"
    with open(log_path, "r") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    os.remove(log_path)

    assert calls == [[str(f)] for f in range(1, 6)], (
        "build_dataset.sh must call generate_features.py once for each frequency 1 through 5; "
        f"observed calls: {calls!r}"
    )


def test_dataset_csv_content():
    """Check that dataset.csv exists and has the exact expected content."""
    csv_path = "/home/user/dataset.csv"
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."

    expected_content = (
        "f,max_error,peak_freq\n"
        "1,0.2222,1.0\n"
        "2,3.3130,2.0\n"
        "3,31.0664,3.0\n"
        "4,250.7850,4.0\n"
        "5,1730.0175,5.0\n"
    )

    with open(csv_path, "r") as f:
        content = f.read()

    # Strip trailing whitespace/newlines for a robust comparison
    assert content.strip() == expected_content.strip(), f"Content of {csv_path} does not match expected output."


def test_scripts_exist_and_permissions():
    """Check that the scripts exist and the bash script is executable."""
    bash_script = "/home/user/build_dataset.sh"
    py_script = "/home/user/generate_features.py"

    assert os.path.exists(bash_script), f"Bash script {bash_script} does not exist."
    assert os.path.exists(py_script), f"Python script {py_script} does not exist."

    st = os.stat(bash_script)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {bash_script} is not executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
