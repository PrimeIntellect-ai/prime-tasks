#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import math
import re

def test_results_file_and_content():
    bin_path = "/home/user/data/embeddings.bin"
    assert os.path.exists(bin_path), f"File {bin_path} is missing."

    with open(bin_path, "rb") as f:
        data = f.read()

    N = 500
    D = 64
    assert len(data) == N * D * 4, "Embeddings file size is incorrect."

    vectors = []
    for i in range(N):
        vec = struct.unpack(f"{D}f", data[i*D*4:(i+1)*D*4])
        vectors.append(vec)

    def dot_product(v1, v2):
        return sum(a*b for a, b in zip(v1, v2))

    def norm(v):
        return math.sqrt(dot_product(v, v))

    def cosine_sim(v1, v2):
        return dot_product(v1, v2) / (norm(v1) * norm(v2))

    removed = [False] * N
    removed_count = 0
    for i in range(N):
        if removed[i]: continue
        for j in range(i+1, N):
            if removed[j]: continue
            if cosine_sim(vectors[i], vectors[j]) > 0.95:
                removed[j] = True
                removed_count += 1

    retained = [vectors[i] for i in range(N) if not removed[i]]
    M = len(retained) * (len(retained) - 1) // 2

    sims = []
    for i in range(len(retained)):
        for j in range(i+1, len(retained)):
            sims.append(cosine_sim(retained[i], retained[j]))

    mean_sim = sum(sims) / M
    std_sim = math.sqrt(sum((s - mean_sim)**2 for s in sims) / (M - 1))
    margin = 1.96 * (std_sim / math.sqrt(M))
    ci_lower = mean_sim - margin
    ci_upper = mean_sim + margin

    results_path = "/home/user/results.txt"
    assert os.path.exists(results_path), f"Results file {results_path} not found. Did you save the output?"

    with open(results_path, "r") as f:
        content = f.read()

    match_removed = re.search(r"Removed Count:\s*(\d+)", content)
    assert match_removed is not None, "Removed Count not found in results.txt or format is incorrect."
    assert int(match_removed.group(1)) == removed_count, f"Expected Removed Count: {removed_count}, found: {match_removed.group(1)}"

    match_mean = re.search(r"Mean Similarity:\s*([+-]?\d*\.?\d+)", content)
    assert match_mean is not None, "Mean Similarity not found in results.txt or format is incorrect."
    assert abs(float(match_mean.group(1)) - mean_sim) < 0.0005, f"Mean Similarity incorrect. Expected ~{mean_sim:.4f}, found: {match_mean.group(1)}"

    match_lower = re.search(r"CI Lower:\s*([+-]?\d*\.?\d+)", content)
    assert match_lower is not None, "CI Lower not found in results.txt or format is incorrect."
    assert abs(float(match_lower.group(1)) - ci_lower) < 0.0005, f"CI Lower incorrect. Expected ~{ci_lower:.4f}, found: {match_lower.group(1)}"

    match_upper = re.search(r"CI Upper:\s*([+-]?\d*\.?\d+)", content)
    assert match_upper is not None, "CI Upper not found in results.txt or format is incorrect."
    assert abs(float(match_upper.group(1)) - ci_upper) < 0.0005, f"CI Upper incorrect. Expected ~{ci_upper:.4f}, found: {match_upper.group(1)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
