#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/probe_analyze_signal.py
import importlib.util
import os
import stat
import numpy as np

script_path = "/home/user/analyze_signal.py"
st = os.lstat(script_path)
assert stat.S_ISREG(st.st_mode), f"{script_path} must be a regular file"

spec = importlib.util.spec_from_file_location("submitted_analyze_signal", script_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(getattr(module, "main", None)), "analyze_signal.py must define main()"
assert callable(getattr(module, "generate_signal", None)), "analyze_signal.py must define generate_signal()"

# Exercise the submitted analysis on the same sampling layout, but make 120 Hz
# dominant. This ensures dominant_freq.txt is produced by spectral analysis
# rather than being a prewritten or hard-coded answer for the original signal.
def probe_signal():
    n = 10_000_000
    t = np.linspace(0, 10, n, endpoint=False, dtype=np.float32)
    y = 0.5 * np.sin(2 * np.pi * 50 * t)
    y += 1.5 * np.sin(2 * np.pi * 120 * t)
    return y.astype(np.float32, copy=False)

module.generate_signal = probe_signal
for path in ("/home/user/energy_diff.txt", "/home/user/dominant_freq.txt"):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

module.main()

with open("/home/user/energy_diff.txt", "r") as f:
    probe_diff = float(f.read().strip())
assert np.isfinite(probe_diff) and probe_diff < 1.0, (
    f"Probe signal Parseval difference must be less than 1.0, got {probe_diff}"
)

with open("/home/user/dominant_freq.txt", "r") as f:
    probe_freq = int(float(f.read().strip()))
assert probe_freq == 120, (
    f"Submitted analysis did not detect the probe's dominant frequency: {probe_freq}"
)
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_energy_diff_file():
    """Verify that energy_diff.txt exists and contains a value less than 1.0."""
    diff_file = "/home/user/energy_diff.txt"
    assert os.path.exists(diff_file), f"File {diff_file} does not exist."

    with open(diff_file, "r") as f:
        content = f.read().strip()

    assert content, f"File {diff_file} is empty."

    try:
        diff_value = float(content)
    except ValueError:
        assert False, f"Content of {diff_file} ('{content}') cannot be parsed as a float."

    assert diff_value < 1.0, f"Energy difference {diff_value} is not less than 1.0."

def test_dominant_freq_file():
    """Verify that dominant_freq.txt exists and contains the correct dominant frequency."""
    freq_file = "/home/user/dominant_freq.txt"
    assert os.path.exists(freq_file), f"File {freq_file} does not exist."

    with open(freq_file, "r") as f:
        content = f.read().strip()

    assert content, f"File {freq_file} is empty."

    try:
        freq_value = int(float(content))
    except ValueError:
        assert False, f"Content of {freq_file} ('{content}') cannot be parsed as an integer."

    assert freq_value == 50, f"Expected dominant frequency to be 50, but got {freq_value}."

def test_analyze_signal_script_exists():
    """Verify that analyze_signal.py still exists."""
    script_file = "/home/user/analyze_signal.py"
    assert os.path.exists(script_file), f"File {script_file} does not exist. You should have modified it, not deleted it."
TEST_EOF

if timeout 300s python3 /tmp/probe_analyze_signal.py \
    && rm -f /home/user/energy_diff.txt /home/user/dominant_freq.txt \
    && timeout 300s python3 /home/user/analyze_signal.py \
    && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
