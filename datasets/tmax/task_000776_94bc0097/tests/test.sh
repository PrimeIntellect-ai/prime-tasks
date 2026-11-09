#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/verify_final_state.py
import csv
import glob
import json
import math
import os

venv_python = "/home/user/venv/bin/python"
assert os.path.isfile(venv_python), (
    f"Virtual environment python not found at {venv_python}. "
    "Make sure you created the venv at /home/user/venv."
)

report_path = "/home/user/report.json"
assert os.path.isfile(report_path), f"Report file not found at {report_path}."

try:
    with open(report_path, "r") as f:
        results = json.load(f)
except json.JSONDecodeError as exc:
    raise AssertionError("The report.json file is not valid JSON.") from exc

expected_keys = {"pearson_correlation", "mse", "most_similar_to_0"}
missing_keys = expected_keys - set(results.keys())
assert not missing_keys, f"Report is missing required keys: {missing_keys}"
assert isinstance(results["pearson_correlation"], (float, int)), "pearson_correlation must be a float"
assert isinstance(results["mse"], (float, int)), "mse must be a float"
assert isinstance(results["most_similar_to_0"], str), "most_similar_to_0 must be a string"

# Import every package the requested environment must provide.
import numpy as np
from scipy.stats import pearsonr
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer

base = "/home/user/dataset_info"
ids = [f"dataset_{i}" for i in range(20)]
descriptions = []
for dataset_id in ids:
    path = os.path.join(base, dataset_id + ".txt")
    assert os.path.isfile(path), f"Missing input description: {path}"
    with open(path, "r") as f:
        descriptions.append(f.read())

with open(os.path.join(base, "metadata.csv"), newline="") as f:
    rows = list(csv.DictReader(f))
years_by_id = {row["dataset_id"]: int(row["year_created"]) for row in rows}
assert all(dataset_id in years_by_id for dataset_id in ids), "metadata.csv is missing dataset IDs"
years = np.asarray([years_by_id[dataset_id] for dataset_id in ids], dtype=float)

# Prefer an already downloaded copy of the required model, while retaining the
# normal model-name fallback if it is available through the local cache/network.
model_source = "all-MiniLM-L6-v2"
cache_patterns = [
    "/home/user/.cache/huggingface/hub/models--sentence-transformers--all-MiniLM-L6-v2/snapshots/*",
    "/root/.cache/huggingface/hub/models--sentence-transformers--all-MiniLM-L6-v2/snapshots/*",
]
for pattern in cache_patterns:
    candidates = sorted(p for p in glob.glob(pattern) if os.path.isfile(os.path.join(p, "config.json")))
    if candidates:
        model_source = candidates[-1]
        break

model = SentenceTransformer(model_source)
embeddings = model.encode(descriptions, convert_to_numpy=True)
similarity = cosine_similarity(embeddings)
temporal_difference = np.abs(years[:, None] - years[None, :])
upper = np.triu_indices(20, k=1)
flat_similarity = similarity[upper]
flat_temporal = temporal_difference[upper]

expected_pearson = float(pearsonr(flat_similarity, flat_temporal).statistic)
regression = LinearRegression()
regression.fit(flat_similarity.reshape(-1, 1), flat_temporal)
predictions = regression.predict(flat_similarity.reshape(-1, 1))
expected_mse = float(mean_squared_error(flat_temporal, predictions))

row_zero = similarity[0].copy()
row_zero[0] = -np.inf
expected_similar = ids[int(np.argmax(row_zero))]

actual_pearson = float(results["pearson_correlation"])
actual_mse = float(results["mse"])
assert math.isfinite(actual_pearson), "pearson_correlation must be finite"
assert math.isfinite(actual_mse), "mse must be finite"
assert abs(actual_pearson - expected_pearson) <= 1e-4, (
    f"Incorrect pearson_correlation: expected {expected_pearson}, got {actual_pearson}"
)
assert abs(actual_mse - expected_mse) <= 1e-4, (
    f"Incorrect mse: expected {expected_mse}, got {actual_mse}"
)
assert results["most_similar_to_0"] == expected_similar, (
    f"Incorrect most_similar_to_0: expected {expected_similar}, "
    f"got {results['most_similar_to_0']}"
)

# Preserve the original verifier's explicit assertion.
actual_similar = results.get("most_similar_to_0")
assert actual_similar == "dataset_10", (
    f"Expected most_similar_to_0 to be 'dataset_10', but got '{actual_similar}'."
)
TEST_EOF

if /home/user/venv/bin/python /tmp/verify_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
