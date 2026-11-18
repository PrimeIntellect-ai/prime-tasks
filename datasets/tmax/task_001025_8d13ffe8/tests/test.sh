#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "annoy:annoy"; do
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
import csv
import json
import math
import os
import subprocess
import sys
import tempfile
import uuid

import numpy as np
import pytest

TEST_CSV = "/app/data/test_set_embeddings.csv"
INDEX_PATH = "/home/user/test_index.ann"
DETECTOR_PATH = "/home/user/detector.py"


def load_test_vectors():
    vectors = []
    with open(TEST_CSV, newline="") as f:
        for row in csv.reader(f):
            assert len(row) == 129
            vectors.append(np.asarray([float(x) for x in row[1:]], dtype=np.float64))
    return np.asarray(vectors)


def test_annoy_installed_and_working():
    """Verifies that annoy was fixed, compiled, and installed."""
    try:
        from annoy import AnnoyIndex
        AnnoyIndex(128, "angular")
    except ImportError as e:
        pytest.fail(f"Failed to import AnnoyIndex: {e}")
    except Exception as e:
        pytest.fail(f"Failed to instantiate AnnoyIndex: {e}")


def test_index_file_exists_and_contains_test_set():
    """Verifies that the saved artifact is a valid angular index of the test rows."""
    from annoy import AnnoyIndex

    assert os.path.isfile(INDEX_PATH), f"The test set index file is missing at {INDEX_PATH}"
    assert os.path.getsize(INDEX_PATH) > 0, f"The test set index file at {INDEX_PATH} is empty"

    vectors = load_test_vectors()
    idx = AnnoyIndex(128, "angular")
    try:
        loaded = idx.load(INDEX_PATH)
    except Exception as e:
        pytest.fail(f"The index cannot be loaded as a 128-dimensional angular Annoy index: {e}")
    assert loaded, "AnnoyIndex.load returned false"
    assert idx.get_n_items() == len(vectors), (
        f"Index contains {idx.get_n_items()} items, expected {len(vectors)}"
    )

    # Every source vector must have a virtually identical item in the index.
    for row_number, vector in enumerate(vectors):
        ids, distances = idx.get_nns_by_vector(
            vector.tolist(), 1, search_k=max(10000, len(vectors) * 20),
            include_distances=True,
        )
        assert ids and distances, f"No neighbor returned for test row {row_number}"
        assert distances[0] < 1e-3, (
            f"Test row {row_number} is not represented in the index; nearest distance={distances[0]}"
        )


def run_detector(input_dir, output_path):
    try:
        subprocess.run(
            [sys.executable, DETECTOR_PATH, input_dir, output_path],
            check=True,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Detector failed for {input_dir}:\nstdout:\n{e.stdout}\nstderr:\n{e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out for {input_dir}")

    assert os.path.isfile(output_path), f"Output JSON log not created at {output_path}"
    try:
        with open(output_path) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        pytest.fail(f"Failed to read JSON from {output_path}: {e}")


def test_detector_script_against_original_corpora():
    """Retains the original clean and evil corpus assertions."""
    assert os.path.isfile(DETECTOR_PATH), f"Detector script not found at {DETECTOR_PATH}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_out = "/tmp/clean_output.json"
    evil_out = "/tmp/evil_output.json"

    clean_results = run_detector(clean_dir, clean_out)
    evil_results = run_detector(evil_dir, evil_out)

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]

    clean_modified = []
    for path in clean_files:
        if path not in clean_results:
            clean_modified.append(f"{os.path.basename(path)} (missing in output)")
        elif clean_results[path] is not True:
            clean_modified.append(f"{os.path.basename(path)} (falsely rejected)")

    evil_bypassed = []
    for path in evil_files:
        if path not in evil_results:
            evil_bypassed.append(f"{os.path.basename(path)} (missing in output)")
        elif evil_results[path] is not False:
            evil_bypassed.append(f"{os.path.basename(path)} (falsely accepted)")

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: " + ", ".join(evil_bypassed))
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: " + ", ".join(clean_modified))
    if errors:
        pytest.fail(" | ".join(errors))


def angular_distance_to_set(vector, normalized_tests):
    vector = vector / np.linalg.norm(vector)
    best_cosine = float(np.max(normalized_tests @ vector))
    best_cosine = min(1.0, max(-1.0, best_cosine))
    return math.sqrt(max(0.0, 2.0 - 2.0 * best_cosine))


def vector_at_angular_distance(base, direction, distance):
    base = base / np.linalg.norm(base)
    direction = direction - np.dot(direction, base) * base
    direction = direction / np.linalg.norm(direction)
    cosine = 1.0 - distance * distance / 2.0
    sine = math.sqrt(1.0 - cosine * cosine)
    return cosine * base + sine * direction


def write_csv(path, vectors):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        for i, vector in enumerate(vectors):
            writer.writerow([f"row_{uuid.uuid4().hex}_{i}"] + [format(float(x), ".17g") for x in vector])


def test_detector_on_randomized_mixed_corpus_with_derived_answers():
    """Exercises one unpredictably named directory containing both accepted and rejected files."""
    assert os.path.isfile(DETECTOR_PATH), f"Detector script not found at {DETECTOR_PATH}"

    tests = load_test_vectors()
    normalized_tests = tests / np.linalg.norm(tests, axis=1, keepdims=True)
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))

    base = normalized_tests[int(rng.integers(0, len(normalized_tests)))]
    direction = rng.normal(size=128)
    near_leak = vector_at_angular_distance(base, direction, 0.04)
    near_clean = vector_at_angular_distance(base, direction, 0.06)

    def random_clean():
        for _ in range(1000):
            candidate = rng.normal(size=128)
            candidate /= np.linalg.norm(candidate)
            if angular_distance_to_set(candidate, normalized_tests) >= 0.05:
                return candidate
        pytest.fail("Unable to generate a clean test vector")

    batches = [
        [random_clean(), random_clean()],
        [near_clean],
        [base.copy()],
        [random_clean(), near_leak],
        [random_clean()],
        [near_clean, random_clean(), near_clean],
    ]

    corpus_dir = tempfile.mkdtemp(prefix=f"batch_{uuid.uuid4().hex}_", dir="/tmp")
    expected = {}
    for vectors in batches:
        path = os.path.abspath(os.path.join(corpus_dir, f"{uuid.uuid4().hex}.csv"))
        write_csv(path, vectors)
        expected[path] = all(
            angular_distance_to_set(np.asarray(v), normalized_tests) >= 0.05
            for v in vectors
        )

    assert any(expected.values()) and not all(expected.values()), "Generated corpus must mix clean and leaked files"

    output_path = os.path.join("/tmp", f"result_{uuid.uuid4().hex}.json")
    results = run_detector(corpus_dir, output_path)

    assert isinstance(results, dict), "Detector output must be a JSON dictionary"
    assert set(results) == set(expected), (
        f"Output keys differ from processed CSV paths; missing={set(expected) - set(results)}, "
        f"extra={set(results) - set(expected)}"
    )
    for path, answer in expected.items():
        assert type(results[path]) is bool, f"Result for {path} is not a JSON boolean"
        assert results[path] is answer, (
            f"Incorrect classification for randomized file {path}: "
            f"expected {answer}, got {results[path]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
