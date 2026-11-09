#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import sys

venv_dir = "/home/user/venv"
python_bin = os.path.join(venv_dir, "bin", "python")
assert os.path.isdir(venv_dir), f"Virtual environment directory {venv_dir} is missing."
assert os.path.isfile(python_bin), f"Python executable not found in venv at {python_bin}."
assert os.path.abspath(sys.prefix) == os.path.abspath(venv_dir), \
    f"Verifier is not running with the required virtual environment: {sys.prefix}"

try:
    import numpy as np
    import scipy
    from scipy.stats import ttest_ind
except ImportError as exc:
    raise AssertionError(f"NumPy and SciPy must be installed in {venv_dir}: {exc}")

venv_real = os.path.realpath(venv_dir)
for name, module in (("numpy", np), ("scipy", scipy)):
    module_path = os.path.realpath(module.__file__)
    assert os.path.commonpath([venv_real, module_path]) == venv_real, \
        f"{name} was not imported from the required virtual environment: {module_path}"

output_path = "/home/user/output.json"
assert os.path.isfile(output_path), f"File {output_path} is missing."
with open(output_path, "r") as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f"File {output_path} is not a valid JSON file.")

required_keys = [
    "num_filtered_sequences",
    "max_hamming_distance",
    "top_singular_value",
    "t_statistic",
    "p_value",
]
for key in required_keys:
    assert key in data, f"Key '{key}' is missing from output.json."

assert isinstance(data["top_singular_value"], float), "top_singular_value must be a float."
assert isinstance(data["t_statistic"], float), "t_statistic must be a float."
assert isinstance(data["p_value"], float), "p_value must be a float."

seqs = {}
current_id = None
current_parts = []
with open("/home/user/data/seqs.fasta", "r") as f:
    for raw_line in f:
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(">"):
            if current_id is not None:
                seqs[current_id] = "".join(current_parts)
            current_id = line[1:]
            current_parts = []
        else:
            assert current_id is not None, "Malformed FASTA input."
            current_parts.append(line)
if current_id is not None:
    seqs[current_id] = "".join(current_parts)

filtered_seqs = {key: value for key, value in seqs.items() if "GATCA" in value}
sorted_keys = sorted(filtered_seqs)
expected_num_filtered = len(sorted_keys)
assert data["num_filtered_sequences"] == expected_num_filtered, \
    f"Incorrect num_filtered_sequences. Expected {expected_num_filtered}, got {data['num_filtered_sequences']}."

max_hamming = 0
for i in range(len(sorted_keys)):
    for j in range(i, len(sorted_keys)):
        s1 = filtered_seqs[sorted_keys[i]]
        s2 = filtered_seqs[sorted_keys[j]]
        dist = sum(1 for a, b in zip(s1, s2) if a != b)
        max_hamming = max(max_hamming, dist)
assert data["max_hamming_distance"] == max_hamming, \
    f"Incorrect max_hamming_distance. Expected {max_hamming}, got {data['max_hamming_distance']}."

n = len(sorted_keys)
D = np.zeros((n, n), dtype=float)
for i, seq_id_i in enumerate(sorted_keys):
    for j, seq_id_j in enumerate(sorted_keys):
        D[i, j] = sum(
            a != b for a, b in zip(filtered_seqs[seq_id_i], filtered_seqs[seq_id_j])
        )

U, singular_values, _ = np.linalg.svd(D, full_matrices=False)
X = U * singular_values
first_feature = X[:, 0]

labels = {}
with open("/home/user/data/labels.csv", "r", newline="") as f:
    for row in csv.DictReader(f):
        labels[row["seq_id"]] = int(row["label"])

group0 = np.asarray(
    [first_feature[i] for i, seq_id in enumerate(sorted_keys) if labels[seq_id] == 0],
    dtype=float,
)
group1 = np.asarray(
    [first_feature[i] for i, seq_id in enumerate(sorted_keys) if labels[seq_id] == 1],
    dtype=float,
)
result = ttest_ind(group0, group1, equal_var=False)

expected_top = float(round(float(singular_values[0]), 4))
expected_t = float(round(float(result.statistic), 4))
expected_p = float(round(float(result.pvalue), 4))

assert data["top_singular_value"] == expected_top, \
    f"Incorrect top_singular_value. Expected {expected_top}, got {data['top_singular_value']}."
# The sign of an SVD singular vector is arbitrary, so either corresponding t-statistic sign is valid.
assert data["t_statistic"] in (expected_t, -expected_t), \
    f"Incorrect t_statistic. Expected {expected_t} (or {-expected_t} under the equivalent SVD sign), got {data['t_statistic']}."
assert data["p_value"] == expected_p, \
    f"Incorrect p_value. Expected {expected_p}, got {data['p_value']}."
TEST_EOF

if /home/user/venv/bin/python /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
