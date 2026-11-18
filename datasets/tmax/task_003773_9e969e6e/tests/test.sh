#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pwd
import subprocess

VENV_PYTHON = "/home/user/bio_env/bin/python"
RESULTS_FILE = "/home/user/results.json"
FASTA_FILE = "/home/user/data/sequences.fasta"

# Preserve the original existence assertions.
assert os.path.exists(VENV_PYTHON), f"Virtual environment Python executable not found at {VENV_PYTHON}"
assert os.path.isfile(RESULTS_FILE), f"File {RESULTS_FILE} does not exist."

# The requested packages must be installed in the requested environment.
subprocess.run(
    [VENV_PYTHON, "-c", "import numpy, scipy, Bio"],
    check=True,
    timeout=30,
)

# Locate and execute the analysis script rather than trusting a prewritten JSON file.
candidates = []
for root, dirs, files in os.walk("/home/user"):
    if root == "/home/user/bio_env":
        dirs[:] = []
    else:
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache"}]
    if root.startswith("/home/user/data"):
        dirs[:] = []
        continue
    for name in files:
        path = os.path.join(root, name)
        if path == RESULTS_FILE or not os.path.isfile(path):
            continue
        try:
            if os.path.getsize(path) > 2_000_000:
                continue
            with open(path, "r", encoding="utf-8") as handle:
                source = handle.read()
        except (OSError, UnicodeDecodeError):
            continue
        lowered = source.lower()
        if "minimize" in lowered and "sequences.fasta" in lowered and "results.json" in lowered:
            candidates.append(path)

assert candidates, "No Python analysis script using minimize and the required input/output files was found."

user_info = pwd.getpwnam("user")
def demote():
    os.setgid(user_info.pw_gid)
    os.setuid(user_info.pw_uid)

executed = False
errors = []
for script in sorted(candidates):
    try:
        if os.path.exists(RESULTS_FILE):
            os.unlink(RESULTS_FILE)
        completed = subprocess.run(
            [VENV_PYTHON, script],
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user", "PATH": "/home/user/bio_env/bin:" + os.environ.get("PATH", "")},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
            preexec_fn=demote,
        )
        if completed.returncode == 0 and os.path.isfile(RESULTS_FILE):
            executed = True
            break
        errors.append(f"{script}: exit {completed.returncode}: {completed.stderr[-500:]}")
    except Exception as exc:
        errors.append(f"{script}: {exc}")

assert executed, "No analysis script successfully regenerated results.json. " + " | ".join(errors)

import numpy as np
from Bio import SeqIO
from scipy.optimize import minimize

with open(RESULTS_FILE, "r") as handle:
    try:
        data = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {RESULTS_FILE} does not contain valid JSON.") from exc

# Preserve the original required-key checks.
assert "optimal_weights" in data, "Missing 'optimal_weights' key in results.json."
assert "seq_train_power" in data, "Missing 'seq_train_power' key in results.json."
assert "ranking" in data, "Missing 'ranking' key in results.json."

weights = data["optimal_weights"]
assert isinstance(weights, dict), "'optimal_weights' should be a dictionary."
for base in ["A", "C", "G", "T"]:
    assert base in weights, f"Missing base '{base}' in 'optimal_weights'."
    assert isinstance(weights[base], (int, float)), f"Weight for '{base}' must be a number."
    assert not isinstance(weights[base], bool) and math.isfinite(weights[base]), f"Weight for '{base}' must be finite."

power = data["seq_train_power"]
assert isinstance(power, (int, float)), "'seq_train_power' must be a number."
assert not isinstance(power, bool) and math.isfinite(power), "'seq_train_power' must be finite."
assert power > 0.1, f"'seq_train_power' is expected to be > 0.1, got {power}."

ranking = data["ranking"]
assert isinstance(ranking, list), "'ranking' should be a list."
assert len(ranking) == 4, f"'ranking' should contain exactly 4 elements, got {len(ranking)}."
top_two = set(ranking[:2])
assert top_two == {"seq_train", "seq_C"}, f"Top two sequences must be 'seq_train' and 'seq_C', got {ranking[:2]}."
assert ranking[2] == "seq_A", f"The third sequence must be 'seq_A', got '{ranking[2]}'."
assert ranking[3] == "seq_B", f"The fourth sequence must be 'seq_B', got '{ranking[3]}'."

records = list(SeqIO.parse(FASTA_FILE, "fasta"))
sequences = {record.id: str(record.seq).upper() for record in records}
assert "seq_train" in sequences, "seq_train is missing from the FASTA file."
assert len(sequences) == 4, f"Expected four FASTA sequences, found {len(sequences)}."
assert set(ranking) == set(sequences), "Ranking must contain every FASTA sequence ID exactly once."

base_order = ["A", "C", "G", "T"]
submitted_w = np.array([float(weights[b]) for b in base_order], dtype=float)
submitted_norm = float(np.linalg.norm(submitted_w))
assert abs(submitted_norm - 1.0) <= 1e-6, f"Optimal weights are not normalized: norm={submitted_norm}."

def relative_power(sequence, vector):
    assert len(sequence) % 3 == 0, f"Sequence length {len(sequence)} is not divisible by three."
    mapping = dict(zip(base_order, vector))
    signal = np.array([mapping[base] for base in sequence], dtype=float)
    spectrum = np.fft.fft(signal)
    powers = np.abs(spectrum) ** 2
    denominator = float(np.sum(powers))
    assert denominator > 0 and math.isfinite(denominator), "Power-spectrum denominator is invalid."
    return float(powers[len(sequence) // 3] / denominator)

# Recompute the reported power directly from the FASTA and submitted weights.
computed_train_power = relative_power(sequences["seq_train"], submitted_w)
assert abs(float(power) - computed_train_power) <= 1e-6, (
    f"seq_train_power does not match the FFT computation: reported {power}, computed {computed_train_power}."
)

# Independently repeat the specified optimization from the specified initial guess.
train_sequence = sequences["seq_train"]
def objective(vector):
    norm = np.linalg.norm(vector)
    if not np.isfinite(norm) or norm == 0:
        return 1.0
    return -relative_power(train_sequence, np.asarray(vector, dtype=float) / norm)

reference = minimize(
    objective,
    np.array([1.0, 0.5, -0.5, -1.0], dtype=float),
    method="Nelder-Mead",
)
assert reference.success, f"Independent optimization failed: {reference.message}"
reference_power = -float(reference.fun)
assert computed_train_power >= reference_power - 2e-5, (
    f"Submitted weights are not optimal: achieved {computed_train_power}, expected at least {reference_power}."
)

# Recompute every FFT power and ensure the submitted ranking is descending.
all_powers = {seq_id: relative_power(sequence, submitted_w) for seq_id, sequence in sequences.items()}
for left, right in zip(ranking, ranking[1:]):
    assert all_powers[left] + 1e-12 >= all_powers[right], (
        f"Ranking is not descending: {left}={all_powers[left]} is below {right}={all_powers[right]}."
    )
TEST_EOF

if /home/user/bio_env/bin/python /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
