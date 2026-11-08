#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import numpy as np

SOURCE = "/home/user/prepare_data.cpp"
BINARY = "/tmp/prepare_data_submission"
EMBEDDINGS = "/home/user/embeddings.bin"
REFERENCE = "/home/user/ref_vector.txt"
SUMMARY = "/home/user/result_summary.txt"


def parse_summary():
    assert os.path.isfile(SUMMARY), f"File {SUMMARY} does not exist. Did the program write the output?"
    with open(SUMMARY, "r") as f:
        content = f.read()

    count_match = re.search(r"Count:\s*(\d+)", content)
    assert count_match is not None, "Could not find 'Count: <integer>' in result_summary.txt. Check your output format."

    cov_match = re.search(r"MaxCov:\s*([0-9.]+)", content)
    assert cov_match is not None, "Could not find 'MaxCov: <float>' in result_summary.txt. Check your output format."

    return int(count_match.group(1)), float(cov_match.group(1))


def run_submission():
    if os.path.lexists(SUMMARY):
        os.unlink(SUMMARY)
    result = subprocess.run([BINARY], cwd="/home/user", capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return parse_summary()


def make_case():
    rng = np.random.default_rng(secrets.randbits(128))
    n, d = 50000, 10

    ref = rng.normal(size=d)
    ref /= np.linalg.norm(ref)
    ref = ref.astype(np.float32)

    # Rejected vectors are orthogonal to the reference and therefore well below
    # the threshold. Accepted vectors are close to positive multiples of it.
    vectors = rng.normal(size=(n, d))
    ref64 = ref.astype(np.float64)
    vectors -= np.outer(vectors @ ref64, ref64) / np.dot(ref64, ref64)
    vectors = vectors.astype(np.float32)

    wanted = int(rng.integers(25, 90))
    indices = rng.choice(n, size=wanted, replace=False)
    accepted = []
    for idx in indices:
        noise = rng.normal(size=d)
        noise -= ref64 * (np.dot(noise, ref64) / np.dot(ref64, ref64))
        noise *= 0.08 / np.linalg.norm(noise)
        vec = ref64 * rng.uniform(0.8, 2.2) + noise
        vectors[idx] = vec.astype(np.float32)
        accepted.append(vectors[idx].copy())

    return ref, vectors


def oracle(ref, vectors):
    x = vectors.astype(np.float64)
    r = ref.astype(np.float64)
    norms = np.linalg.norm(x, axis=1) * np.linalg.norm(r)
    similarities = np.divide(x @ r, norms, out=np.zeros(x.shape[0]), where=norms != 0)
    selected = x[similarities >= 0.85]
    count = selected.shape[0]
    assert count > 1

    centered = selected - selected.mean(axis=0)
    covariance = centered.T @ centered / (count - 1)
    mask = ~np.eye(10, dtype=bool)
    max_cov = float(np.max(np.abs(covariance[mask])))
    return count, float(f"{max_cov:.4f}")


def test_compiled_program_and_results():
    assert os.path.isfile(SOURCE), f"Required C++ source file {SOURCE} does not exist."

    compilation = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compilation.returncode == 0, (
        f"Could not compile {SOURCE}.\nstdout:\n{compilation.stdout}\n"
        f"stderr:\n{compilation.stderr}"
    )

    with open(EMBEDDINGS, "rb") as f:
        original_embeddings = f.read()
    with open(REFERENCE, "rb") as f:
        original_reference = f.read()
    prior_summary = None
    if os.path.isfile(SUMMARY):
        with open(SUMMARY, "rb") as f:
            prior_summary = f.read()

    original_generated_summary = None
    try:
        # Preserve the verifier's original assertions, but require the compiled
        # submission to produce the file rather than trusting a prewritten one.
        count_val, cov_val = run_submission()
        assert count_val == 1215, f"Expected Count to be 1215, but got {count_val}."
        assert 0.0088 <= cov_val <= 0.0092, f"Expected MaxCov to be around 0.0090, but got {cov_val}."
        with open(SUMMARY, "rb") as f:
            original_generated_summary = f.read()

        # Exercise the same compiled program on fresh 50,000-by-10 datasets.
        # Expected answers are computed from the generated float32 inputs.
        for _ in range(2):
            ref, vectors = make_case()
            vectors.tofile(EMBEDDINGS)
            np.savetxt(REFERENCE, ref.reshape(1, -1), fmt="%.9g", delimiter=" ")

            # Compute against the exact reference values that C++ will parse.
            parsed_ref = np.fromstring(open(REFERENCE).read(), sep=" ", dtype=np.float32)
            expected_count, expected_cov = oracle(parsed_ref, vectors)
            actual_count, actual_cov = run_submission()

            assert actual_count == expected_count, (
                f"Fresh-input Count mismatch: expected {expected_count}, got {actual_count}."
            )
            assert abs(actual_cov - expected_cov) <= 0.00011, (
                f"Fresh-input MaxCov mismatch: expected {expected_cov:.4f}, got {actual_cov}."
            )
    finally:
        with open(EMBEDDINGS, "wb") as f:
            f.write(original_embeddings)
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)

        if os.path.lexists(SUMMARY):
            os.unlink(SUMMARY)
        restored_summary = original_generated_summary
        if restored_summary is None:
            restored_summary = prior_summary
        if restored_summary is not None:
            with open(SUMMARY, "wb") as f:
                f.write(restored_summary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
