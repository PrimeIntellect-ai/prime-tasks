#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import subprocess
import tempfile

import numpy as np

SANITIZER = "/home/user/sanitizer"
ANCHORS = "/home/user/corpora/anchors.txt"


def load_matrix(path):
    arr = np.loadtxt(path, dtype=float, ndmin=2)
    assert arr.ndim == 2 and arr.shape[1] == 50, f"{path} is not a 50-dimensional dataset"
    assert np.isfinite(arr).all(), f"{path} contains non-finite values"
    return arr


def expected_result(input_path, anchors_path):
    data = load_matrix(input_path)
    anchors = load_matrix(anchors_path)
    combined = np.vstack((data, anchors))
    _, singular_values, vt = np.linalg.svd(combined, full_matrices=False)
    projected = combined @ vt[:3].T
    data_projected = projected[:len(data)]
    anchor_projected = projected[len(data):]
    distances = np.linalg.norm(
        data_projected[:, None, :] - anchor_projected[None, :, :], axis=2
    )
    rejected = np.any(distances < 1.50, axis=1)
    return data, data[~rejected], int(rejected.sum()), float(singular_values[0])


def read_output(path, expected_rows):
    assert os.path.isfile(path), "Sanitized output dataset was not created"
    if expected_rows == 0:
        assert open(path, "r").read().strip() == "", "Output should be empty when all rows are rejected"
        return np.empty((0, 50))
    try:
        output = np.loadtxt(path, dtype=float, ndmin=2)
    except Exception as exc:
        raise AssertionError(f"Invalid output dataset: {exc}")
    assert output.shape == (expected_rows, 50), f"Output has shape {output.shape}, expected {(expected_rows, 50)}"
    assert np.isfinite(output).all(), "Output contains non-finite values"
    return output


def validate_run(input_path, anchors_path, expected_clean=None, expected_rejected=None):
    with tempfile.TemporaryDirectory() as tmpdir:
        out_txt = os.path.join(tmpdir, "sanitized.txt")
        out_json = os.path.join(tmpdir, "experiment.json")
        result = subprocess.run(
            [SANITIZER, input_path, anchors_path, out_txt, out_json],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"Sanitizer failed for {input_path}: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(out_json), "Experiment JSON was not created"

        data, computed_clean, computed_rejected, top_singular = expected_result(input_path, anchors_path)
        if expected_clean is None:
            expected_clean = computed_clean
        if expected_rejected is None:
            expected_rejected = computed_rejected

        output = read_output(out_txt, len(expected_clean))
        assert np.allclose(output, expected_clean, rtol=1e-6, atol=2e-6), \
            "Sanitized output does not contain exactly the expected original rows in order"

        raw_log = open(out_json, "r").read()
        try:
            log = json.loads(raw_log)
        except Exception as exc:
            raise AssertionError(f"Invalid experiment JSON: {exc}")
        assert set(log) == {"total_input_vectors", "rejected_vectors", "top_singular_value"}, \
            "Experiment JSON does not match the required schema"
        assert isinstance(log["total_input_vectors"], int) and not isinstance(log["total_input_vectors"], bool)
        assert isinstance(log["rejected_vectors"], int) and not isinstance(log["rejected_vectors"], bool)
        assert log["total_input_vectors"] == len(data), "Incorrect total_input_vectors"
        assert log["rejected_vectors"] == expected_rejected, "Incorrect rejected_vectors"
        assert isinstance(log["top_singular_value"], (int, float)) and not isinstance(log["top_singular_value"], bool)
        assert np.isfinite(float(log["top_singular_value"])), "Invalid top_singular_value"
        tolerance = max(0.002, abs(top_singular) * 2e-4)
        assert abs(float(log["top_singular_value"]) - top_singular) <= tolerance, \
            f"Incorrect top_singular_value: got {log['top_singular_value']}, expected {top_singular}"
        token = re.search(r'"top_singular_value"\s*:\s*(-?(?:\d+\.\d+)(?:[eE][+-]?\d+)?)', raw_log)
        assert token and len(token.group(1).split(".", 1)[1].split("e", 1)[0].split("E", 1)[0]) >= 3, \
            "top_singular_value must be written with at least three decimal places"


def test_sanitizer_executable_exists():
    assert os.path.isfile(SANITIZER), f"Sanitizer binary not found at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer binary at {SANITIZER} is not executable"
    assert os.path.isfile("/home/user/sanitizer.c"), "C source not found at /home/user/sanitizer.c"
    with open(SANITIZER, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "Sanitizer is not a compiled native executable"
    symbols = subprocess.run(["nm", SANITIZER], capture_output=True, text=True)
    assert symbols.returncode == 0 and re.search(r"\bsvdLAS2A?\b", symbols.stdout), \
        "Sanitizer does not appear to be linked with and use svdlibc"


def test_libsvd_compiled():
    lib_path = "/app/svdlibc/libsvd.a"
    assert os.path.isfile(lib_path), f"Static library {lib_path} was not compiled successfully."


def test_clean_corpus_preserved():
    clean_files = sorted(glob.glob("/hidden/eval/clean/*"))
    assert len(clean_files) > 0, "No clean corpus files found in /hidden/eval/clean/"
    for path in clean_files:
        original = load_matrix(path)
        validate_run(path, ANCHORS, expected_clean=original, expected_rejected=0)


def test_evil_corpus_rejected():
    evil_files = sorted(glob.glob("/hidden/eval/evil/*"))
    assert len(evil_files) > 0, "No evil corpus files found in /hidden/eval/evil/"
    for path in evil_files:
        _, expected_clean, rejected, _ = expected_result(path, ANCHORS)
        assert rejected > 0, f"Evaluation corpus {path} contains no rejectable vectors"
        validate_run(path, ANCHORS, expected_clean=expected_clean, expected_rejected=rejected)


def test_randomized_svd_filtering_and_output():
    # All rows lie in a freshly generated three-dimensional subspace. Therefore
    # retaining three singular dimensions preserves their distances, while the
    # random rotation and temporary paths prevent corpus/path-based reporting.
    rng = np.random.default_rng()
    for case in range(2):
        basis, _ = np.linalg.qr(rng.normal(size=(50, 3)))
        anchor_coeff = rng.normal(0.0, 4.0, size=(7, 3))

        near = []
        for i in range(8):
            direction = rng.normal(size=3)
            direction /= np.linalg.norm(direction)
            near.append(anchor_coeff[i % len(anchor_coeff)] + direction * rng.uniform(0.2, 1.0))

        far = []
        while len(far) < 10:
            candidate = rng.normal(0.0, 7.0, size=3)
            if np.min(np.linalg.norm(anchor_coeff - candidate, axis=1)) > 2.5:
                far.append(candidate)

        data_coeff = np.vstack((near, far))
        rng.shuffle(data_coeff)
        data = data_coeff @ basis.T
        anchors = anchor_coeff @ basis.T

        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = os.path.join(tmpdir, f"input_{case}_{rng.integers(1 << 60)}.txt")
            anchors_path = os.path.join(tmpdir, f"anchors_{case}_{rng.integers(1 << 60)}.txt")
            np.savetxt(input_path, data, fmt="%.9f")
            np.savetxt(anchors_path, anchors, fmt="%.9f")
            _, expected_clean, rejected, _ = expected_result(input_path, anchors_path)
            assert 0 < rejected < len(data), "Internal randomized test did not contain both classes"
            validate_run(input_path, anchors_path, expected_clean, rejected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
