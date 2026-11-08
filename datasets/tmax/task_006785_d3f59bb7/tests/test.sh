#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import numpy as np

HOME = "/home/user"
SOURCE = f"{HOME}/process_embeddings.c"
EXECUTABLE = f"{HOME}/process_embeddings"
RESULTS = f"{HOME}/results.log"
EMBEDDINGS = f"{HOME}/embeddings.bin"
NUM_VECTORS = 100000
DIM = 16


def expected_dataset_bytes():
    rng = np.random.RandomState(42)
    return rng.randn(NUM_VECTORS, DIM).astype(np.float32).tobytes(order="C")


def compute_expected(embeddings):
    counts = [0] * NUM_VECTORS
    state = 42
    for _ in range(100 * NUM_VECTORS):
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        counts[state % NUM_VECTORS] += 1

    counts = np.asarray(counts, dtype=np.float64)
    centroid = (embeddings.astype(np.float64).T @ counts) / (100.0 * NUM_VECTORS)
    distances = np.sum((embeddings.astype(np.float64) - centroid) ** 2, axis=1)
    indices = np.lexsort((np.arange(NUM_VECTORS), distances))[:5].tolist()
    return centroid, indices


def test_submission():
    # Preserve the original artifact-existence assertions and require real files.
    assert os.path.exists(SOURCE), "C source file is missing."
    assert os.path.isfile(SOURCE), "C source path is not a regular file."
    assert os.path.exists(EXECUTABLE), "Compiled executable is missing."
    assert os.path.isfile(EXECUTABLE), "Compiled executable is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), "Compiled executable is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled executable is not an ELF binary."
    assert os.path.exists(RESULTS), "Results log file is missing."

    # Ensure the writable input has not been replaced or modified.
    assert os.path.isfile(EMBEDDINGS) and not os.path.islink(EMBEDDINGS), \
        "embeddings.bin must be the original regular file."
    with open(EMBEDDINGS, "rb") as f:
        dataset_bytes = f.read()
    trusted_bytes = expected_dataset_bytes()
    assert len(dataset_bytes) == NUM_VECTORS * DIM * 4, \
        "embeddings.bin has unexpected size."
    assert dataset_bytes == trusted_bytes, "embeddings.bin was modified."

    embeddings = np.frombuffer(trusted_bytes, dtype=np.float32).reshape(NUM_VECTORS, DIM)
    expected_centroid, expected_indices = compute_expected(embeddings)

    # Compile the submitted source with the required command and execute the
    # resulting demanded artifact, forcing it to regenerate results.log.
    os.remove(RESULTS)
    subprocess.run(
        ["/usr/bin/gcc", "-O3", SOURCE, "-o", EXECUTABLE, "-lm"],
        check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    subprocess.run(
        [EXECUTABLE], check=True, timeout=180, cwd=HOME,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    assert os.path.exists(RESULTS), "Running the program did not produce results.log."
    assert os.path.isfile(RESULTS), "results.log is not a regular file."

    # The program must not alter its input while running.
    with open(EMBEDDINGS, "rb") as f:
        assert f.read() == trusted_bytes, "The program modified embeddings.bin."

    with open(RESULTS, "r", encoding="utf-8") as f:
        log_content = f.read().strip().splitlines()

    assert len(log_content) >= 3, "results.log must contain at least 3 lines."
    centroid_line, indices_line, time_line = log_content[:3]

    assert centroid_line.startswith("Centroid: "), \
        "First line must start with 'Centroid: '"
    assert indices_line.startswith("Closest Indices: "), \
        "Second line must start with 'Closest Indices: '"
    assert time_line.startswith("Search Time: ") and time_line.endswith(" us"), \
        "Third line must format Search Time correctly."

    centroid_text = centroid_line[len("Centroid: "):]
    centroid_tokens = centroid_text.split(" ")
    assert len(centroid_tokens) == DIM, "Centroid must contain exactly 16 values."
    assert all(re.fullmatch(r"-?\d+\.\d{3}", token) for token in centroid_tokens), \
        "Every centroid value must use exactly three decimal places."
    expected_centroid_line = "Centroid: " + " ".join(
        f"{value:.3f}" for value in expected_centroid
    )
    assert centroid_line == expected_centroid_line, \
        f"Expected '{expected_centroid_line}', but got '{centroid_line}'"

    expected_indices_line = "Closest Indices: " + ", ".join(
        map(str, expected_indices)
    )
    assert indices_line == expected_indices_line, \
        f"Expected '{expected_indices_line}', but got '{indices_line}'"

    time_match = re.fullmatch(r"Search Time: (\d+) us", time_line)
    assert time_match, "Search Time must be an integer number of microseconds."
    assert int(time_match.group(1)) > 0, "Search Time must be positive."


if __name__ == "__main__":
    test_submission()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
