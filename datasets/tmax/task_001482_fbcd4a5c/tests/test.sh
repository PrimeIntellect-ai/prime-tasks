#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import subprocess

import numpy as np
import pytest


def test_pipeline_execution_and_mse():
    script_path = "/home/user/pipeline.sh"
    output_path = "/home/user/top10.txt"
    csv_path = "/home/user/profiles.csv"
    embedder_path = "/app/user_embedder"

    # Check script exists and is executable
    assert os.path.exists(script_path), f"Script {script_path} not found."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    # Execute the pipeline script
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}\nStderr: {result.stderr}"

    # Check output file exists
    assert os.path.exists(output_path), f"Output file {output_path} not found."

    # Generate ground-truth embeddings
    with open(csv_path, "r") as f:
        lines = f.readlines()

    cleaned_lines = []
    for line in lines:
        parts = line.strip().split(",")
        cleaned_parts = [p if p != "" else "0.0" for p in parts]
        cleaned_lines.append(" ".join(cleaned_parts))

    cleaned_input = "\n".join(cleaned_lines) + "\n"
    embed_result = subprocess.run(
        [embedder_path], input=cleaned_input, capture_output=True, text=True
    )
    assert embed_result.returncode == 0, f"Failed to run embedder for truth generation. Stderr: {embed_result.stderr}"

    embeddings = []
    for line in embed_result.stdout.strip().split("\n"):
        if line.strip():
            embeddings.append([float(x) for x in line.strip().split()])
    embeddings = np.array(embeddings)

    # Derive the globally closest 10 unique pairs. The heap stores the worst
    # retained candidate at its root using negated (distance, RowA, RowB).
    closest = []
    for i in range(len(embeddings) - 1):
        deltas = embeddings[i + 1:] - embeddings[i]
        distances = np.sqrt(np.einsum("ij,ij->i", deltas, deltas))
        for offset, distance in enumerate(distances):
            row_a = i + 1
            row_b = i + offset + 2
            entry = (-float(distance), -row_a, -row_b)
            if len(closest) < 10:
                heapq.heappush(closest, entry)
            elif entry > closest[0]:
                heapq.heapreplace(closest, entry)

    expected_top10 = sorted(
        [(-distance, -row_a, -row_b) for distance, row_a, row_b in closest],
        key=lambda item: (item[0], item[1], item[2]),
    )

    # Read the output and compute MSE
    predicted_distances = []
    true_distances = []
    submitted = []

    with open(output_path, "r") as f:
        out_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(out_lines) == 10, f"Expected exactly 10 lines in {output_path}, but got {len(out_lines)}."

    for line in out_lines:
        parts = line.split()
        assert len(parts) == 3, f"Invalid line format in {output_path}: '{line}'. Expected 'RowA RowB Distance'."

        try:
            row_a = int(parts[0])
            row_b = int(parts[1])
            dist = float(parts[2])
        except ValueError:
            pytest.fail(f"Could not parse numeric values from line: '{line}'")

        assert row_a < row_b, f"RowA should be less than RowB, got {row_a} and {row_b}."
        assert 1 <= row_a <= len(embeddings), f"RowA {row_a} is out of bounds."
        assert 1 <= row_b <= len(embeddings), f"RowB {row_b} is out of bounds."

        idx_a = row_a - 1
        idx_b = row_b - 1
        true_dist = np.linalg.norm(embeddings[idx_a] - embeddings[idx_b])

        submitted.append((row_a, row_b, dist))
        predicted_distances.append(dist)
        true_distances.append(true_dist)

    # Require unique pairs, the mandated output ordering, and the actual global
    # top 10 pair identities rather than merely validating arbitrary distances.
    submitted_pairs = [(row_a, row_b) for row_a, row_b, _ in submitted]
    assert len(set(submitted_pairs)) == 10, "The output must contain 10 unique row pairs."
    assert submitted == sorted(submitted, key=lambda item: (item[2], item[0], item[1])), \
        "Output is not sorted by Distance, then RowA, then RowB."

    expected_pairs = [(row_a, row_b) for _, row_a, row_b in expected_top10]
    assert submitted_pairs == expected_pairs, \
        f"Submitted pairs are not the globally closest 10 pairs. Expected {expected_pairs}, got {submitted_pairs}."

    predicted_distances = np.array(predicted_distances)
    true_distances = np.array(true_distances)

    mse = np.mean((predicted_distances - true_distances) ** 2)
    threshold = 1e-4
    assert mse <= threshold, f"Calculated MSE {mse:.6e} exceeds the threshold of {threshold}. Predicted distances might be incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
