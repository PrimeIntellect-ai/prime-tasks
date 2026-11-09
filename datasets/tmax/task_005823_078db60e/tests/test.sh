#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import subprocess
import sys
import pytest
import numpy as np
import faiss
from sklearn.decomposition import PCA


def test_experiment_results_json():
    json_path = "/home/user/experiment_results.json"
    assert os.path.isfile(json_path), f"Expected log file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    expected_keys = {
        "time_1_thread",
        "time_4_threads",
        "explained_variance_ratio_sum",
        "num_raw_vectors",
        "num_clean_vectors"
    }

    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"JSON is missing keys: {missing_keys}"
    assert set(data.keys()) == expected_keys, f"JSON must contain exactly these keys: {expected_keys}"

    assert isinstance(data["time_1_thread"], (int, float)), "time_1_thread must be a number"
    assert data["time_1_thread"] > 0, "time_1_thread must be > 0"

    assert isinstance(data["time_4_threads"], (int, float)), "time_4_threads must be a number"
    assert data["time_4_threads"] > 0, "time_4_threads must be > 0"

    assert isinstance(data["explained_variance_ratio_sum"], (int, float)), "explained_variance_ratio_sum must be a number"
    assert 0 < data["explained_variance_ratio_sum"] <= 1.0, "explained_variance_ratio_sum must be between 0 and 1"

    assert data["num_raw_vectors"] == 5000, f"Expected num_raw_vectors to be 5000, got {data['num_raw_vectors']}"
    assert data["num_clean_vectors"] == 4900, f"Expected num_clean_vectors to be 4900, got {data['num_clean_vectors']}"


def test_clean_embeddings_file():
    clean_path = "/home/user/clean_embeddings.npy"
    assert os.path.isfile(clean_path), f"Expected clean embeddings file {clean_path} does not exist."

    # Check file size to ensure it matches 4900 vectors of 512 float32s
    # 4900 * 512 * 4 bytes = 10035200 bytes. With .npy header (typically 128 bytes), it should be slightly larger.
    file_size = os.path.getsize(clean_path)
    expected_data_size = 4900 * 512 * 4

    assert file_size >= expected_data_size, f"File size {file_size} is too small to contain 4900 vectors of 512 float32s."
    assert file_size < expected_data_size + 1024, f"File size {file_size} is too large, expected around {expected_data_size} bytes."


@pytest.fixture(scope="session")
def independently_computed_results():
    raw = np.load("/home/user/raw_embeddings.npy", allow_pickle=False)
    assert raw.shape == (5000, 512)
    assert raw.dtype == np.float32

    pca = PCA(n_components=64, random_state=42)
    reduced = np.ascontiguousarray(pca.fit_transform(raw).astype(np.float32, copy=False))

    index = faiss.IndexFlatL2(64)
    index.add(reduced)
    limits, distances, neighbors = index.range_search(reduced, 1e-4)

    keep = np.ones(raw.shape[0], dtype=bool)
    for i in range(raw.shape[0]):
        start, end = int(limits[i]), int(limits[i + 1])
        ids = neighbors[start:end]
        dists = distances[start:end]
        if np.any((ids < i) & (dists < 1e-4)):
            keep[i] = False

    return raw, raw[keep], float(pca.explained_variance_ratio_.sum())


def _fresh_faiss_time(thread_count):
    code = r'''import json, time
import numpy as np
import faiss
raw = np.ascontiguousarray(np.load("/home/user/raw_embeddings.npy", allow_pickle=False), dtype=np.float32)
assert faiss.omp_get_max_threads() == THREADS
index = faiss.IndexFlatL2(512)
index.add(raw)
start = time.perf_counter()
d, i = index.search(raw, 5)
elapsed = time.perf_counter() - start
assert d.shape == (5000, 5) and i.shape == (5000, 5)
print(json.dumps({"elapsed": elapsed}))
'''.replace("THREADS", str(thread_count))
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(thread_count)
    completed = subprocess.run(
        [sys.executable, "-c", code],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
        check=True,
    )
    return float(json.loads(completed.stdout.strip().splitlines()[-1])["elapsed"])


def test_outputs_match_independent_computation(independently_computed_results):
    raw, expected_clean, expected_variance = independently_computed_results
    clean = np.load("/home/user/clean_embeddings.npy", allow_pickle=False)

    assert clean.dtype == np.float32, f"Clean embeddings must be float32, got {clean.dtype}"
    assert clean.shape == expected_clean.shape, f"Expected clean shape {expected_clean.shape}, got {clean.shape}"
    assert np.array_equal(clean, expected_clean), "Clean embeddings do not contain exactly the expected original vectors in order"

    with open("/home/user/experiment_results.json", "r") as f:
        data = json.load(f)

    assert type(data["time_1_thread"]) is float, "time_1_thread must be a JSON float"
    assert type(data["time_4_threads"]) is float, "time_4_threads must be a JSON float"
    assert type(data["explained_variance_ratio_sum"]) is float, "explained_variance_ratio_sum must be a JSON float"
    assert type(data["num_raw_vectors"]) is int, "num_raw_vectors must be an integer"
    assert type(data["num_clean_vectors"]) is int, "num_clean_vectors must be an integer"
    assert all(math.isfinite(data[k]) for k in ("time_1_thread", "time_4_threads", "explained_variance_ratio_sum"))

    assert data["num_raw_vectors"] == raw.shape[0]
    assert data["num_clean_vectors"] == expected_clean.shape[0]
    assert np.isclose(data["explained_variance_ratio_sum"], expected_variance, rtol=1e-6, atol=1e-8), (
        f"Expected explained variance sum {expected_variance}, got {data['explained_variance_ratio_sum']}"
    )

    fresh_1 = _fresh_faiss_time(1)
    fresh_4 = _fresh_faiss_time(4)
    for key, fresh in (("time_1_thread", fresh_1), ("time_4_threads", fresh_4)):
        reported = data[key]
        ratio = max(reported, fresh) / min(reported, fresh)
        assert ratio <= 20.0, f"Reported {key}={reported} is not plausible relative to an independent FAISS benchmark ({fresh})"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
