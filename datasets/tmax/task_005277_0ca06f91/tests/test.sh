#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
import sys
import tempfile

SCRIPT = '/home/user/simulate.py'
RESULT = '/home/user/result.txt'
FASTA = '/home/user/data/protein.fasta'
SIGNAL = '/home/user/data/signal.csv'


def test_simulate_py_fixed_step_size():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."
    with open(SCRIPT, 'r') as f:
        content = f.read()

    # Preserve the original source assertion.
    content_no_spaces = content.replace(" ", "")
    assert "(tol/err)" in content_no_spaces or "tol/err" in content_no_spaces, \
        "Step size adaptation formula not corrected (expected 'tol / err')."


def test_fasta_parser_and_adaptive_step_behavior():
    probe = r'''
import importlib.util
import json
import math
import os
import tempfile

spec = importlib.util.spec_from_file_location("submitted_simulate", "/home/user/simulate.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

fd, path = tempfile.mkstemp(suffix=".fasta")
os.close(fd)
try:
    with open(path, "w") as f:
        f.write(">first\nACD\nEFGH\n>second\nTTTTTTTTTT\n")
    parsed_length = module.parse_fasta_length(path)
finally:
    os.unlink(path)

# For f(t,y)=y, t=0, y=1, h=0.1:
# Euler=1.1, Heun=1.105, so err=0.005 (+ the script's 1e-15).
def f(t, y):
    return y

step = module.adaptive_heun_step(f, 0.0, 1.0, 0.1, tol=0.01)
print(json.dumps({"parsed_length": parsed_length, "step": list(step)}))
'''
    completed = subprocess.run(
        [sys.executable, '-c', probe], text=True, capture_output=True, timeout=10
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    assert lines, "Behavior probe produced no output."
    try:
        data = json.loads(lines[-1])
    except Exception as exc:
        raise AssertionError(f"Behavior probe did not produce valid JSON: {completed.stdout!r}") from exc

    assert data['parsed_length'] == 7, \
        "parse_fasta_length must count the residues in the first FASTA sequence."

    t_next, y_next, h_next, success = data['step']
    err = abs(1.105 - 1.1) + 1e-15
    expected_h = 0.9 * 0.1 * (0.01 / err) ** 0.5
    expected_h = max(1e-5, min(expected_h, 0.5))
    assert success is True
    assert math.isclose(t_next, 0.1, rel_tol=0, abs_tol=1e-12)
    assert math.isclose(y_next, 1.105, rel_tol=0, abs_tol=1e-12)
    assert math.isclose(h_next, expected_h, rel_tol=1e-10, abs_tol=1e-12), \
        "adaptive_heun_step does not use the required inverse-error update."


def first_sequence_length(path):
    length = 0
    started = False
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith('>'):
                if started:
                    break
                started = True
            elif started:
                length += len(line)
    return length


def reference_result():
    C = first_sequence_length(FASTA) * 0.12
    times = []
    intensities = []
    with open(SIGNAL, newline='') as f:
        for row in csv.DictReader(f):
            times.append(float(row['time']))
            intensities.append(float(row['intensity']))

    def intensity(t):
        if t <= times[0]:
            return intensities[0]
        if t >= times[-1]:
            return intensities[-1]
        for i in range(len(times) - 1):
            if times[i] <= t <= times[i + 1]:
                w = (t - times[i]) / (times[i + 1] - times[i])
                return intensities[i] * (1.0 - w) + intensities[i + 1] * w
        return 0.0

    def f(t, y):
        return -C * y + intensity(t)

    t = 0.0
    y = 0.0
    h = 0.1
    while t < 5.0:
        if t + h > 5.0:
            h = 5.0 - t
        k1 = f(t, y)
        y_euler = y + h * k1
        k2 = f(t + h, y_euler)
        y_heun = y + (h / 2.0) * (k1 + k2)
        err = abs(y_heun - y_euler) + 1e-15
        h_new = 0.9 * h * (1e-4 / err) ** 0.5
        h_new = max(1e-5, min(h_new, 0.5))
        if err <= 1e-4:
            t += h
            y = y_heun
        h = h_new
    return y


def test_run_simulation_and_result_value():
    # Remove any fabricated or stale result and require the submitted script to
    # recreate it by actually running the simulation.
    if os.path.exists(RESULT):
        os.remove(RESULT)

    completed = subprocess.run(
        [sys.executable, SCRIPT], cwd='/home/user', text=True,
        capture_output=True, timeout=20
    )
    assert completed.returncode == 0, \
        f"Simulation failed:\n{completed.stdout}\n{completed.stderr}"
    assert os.path.isfile(RESULT), f"{RESULT} does not exist after running the simulation."

    with open(RESULT, 'r') as f:
        content = f.read().strip()

    assert re.fullmatch(r'-?\d+\.\d{4}', content), \
        f"Result must be written with exactly four decimal places, got {content!r}."
    try:
        val = float(content)
    except ValueError:
        assert False, f"Content of {RESULT} is not a valid float: '{content}'"

    # Preserve the original range assertion.
    assert 0.0001 <= val <= 0.0010, \
        f"Result value {val} is not within the expected range [0.0001, 0.0010]."

    expected_text = f"{reference_result():.4f}"
    assert content == expected_text, \
        f"Incorrect integrated value: expected {expected_text}, got {content}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
