#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import re
import shutil
import subprocess
import pytest

CSV_PATH = "/home/user/artifacts/pca_projection.csv"
SCRIPT_PATH = "/home/user/process_artifacts.py"
RAW_DIR = "/home/user/raw_logs"
METRICS = ["loss", "accuracy", "epoch_time", "mem_usage", "cpu_load"]

# Execute the submitted ETL from a clean output state. Collection failures are
# reported by pytest, allowing the wrapper to write a reward of 0.
assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist or is not a regular file."
shutil.rmtree("/home/user/artifacts", ignore_errors=True)
subprocess.run(["python3", SCRIPT_PATH], check=True, timeout=120)


def expected_projection():
    records = []
    for path in glob.glob(os.path.join(RAW_DIR, "*.json")):
        with open(path, "r") as f:
            doc = json.load(f)
        records.append((doc["run_id"], [float(doc["metrics"][m]) for m in METRICS]))
    records.sort(key=lambda item: item[0])

    n = len(records)
    d = len(METRICS)
    assert n >= 2
    means = [sum(row[1][j] for row in records) / n for j in range(d)]
    scales = []
    for j in range(d):
        variance = sum((row[1][j] - means[j]) ** 2 for row in records) / n
        scales.append(math.sqrt(variance))
    assert all(scale > 0 for scale in scales), "Test data unexpectedly contains a constant metric."

    standardized = [
        [(values[j] - means[j]) / scales[j] for j in range(d)]
        for _, values in records
    ]
    covariance = [
        [sum(row[i] * row[j] for row in standardized) / n for j in range(d)]
        for i in range(d)
    ]

    # Jacobi eigendecomposition for the small real symmetric covariance matrix.
    a = [row[:] for row in covariance]
    eigenvectors = [[1.0 if i == j else 0.0 for j in range(d)] for i in range(d)]
    for _ in range(200):
        p, q = max(
            ((i, j) for i in range(d) for j in range(i + 1, d)),
            key=lambda pair: abs(a[pair[0]][pair[1]]),
        )
        if abs(a[p][q]) < 1e-14:
            break
        theta = 0.5 * math.atan2(2.0 * a[p][q], a[p][p] - a[q][q])
        c, s = math.cos(theta), math.sin(theta)
        rotation = [[1.0 if i == j else 0.0 for j in range(d)] for i in range(d)]
        rotation[p][p] = c
        rotation[p][q] = -s
        rotation[q][p] = s
        rotation[q][q] = c

        ar = [[sum(a[i][k] * rotation[k][j] for k in range(d)) for j in range(d)] for i in range(d)]
        a = [[sum(rotation[k][i] * ar[k][j] for k in range(d)) for j in range(d)] for i in range(d)]
        eigenvectors = [
            [sum(eigenvectors[i][k] * rotation[k][j] for k in range(d)) for j in range(d)]
            for i in range(d)
        ]

    order = sorted(range(d), key=lambda j: a[j][j], reverse=True)[:2]
    projected = []
    for row in standardized:
        projected.append([sum(row[k] * eigenvectors[k][component] for k in range(d)) for component in order])
    return [record[0] for record in records], projected


def read_and_validate_csv(expected_ids):
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["run_id", "pca_1", "pca_2"], (
            f"Expected header ['run_id', 'pca_1', 'pca_2'], but got {header}"
        )
        rows = list(reader)

    assert len(rows) == len(expected_ids), f"Expected {len(expected_ids)} rows of data, but got {len(rows)}"
    assert all(len(row) == 3 for row in rows), "Every CSV row must contain exactly three columns."
    run_ids = [row[0] for row in rows]
    assert run_ids == expected_ids, f"Expected sorted run_ids {expected_ids}, but got {run_ids}"

    decimal_pattern = re.compile(r"^-?(?:0|[1-9][0-9]*)\.[0-9]{4}$")
    coords = []
    for row in rows:
        for text in row[1:]:
            assert decimal_pattern.fullmatch(text), (
                f"PCA value {text!r} is not written with exactly four decimal places."
            )
        try:
            coords.append((float(row[1]), float(row[2])))
        except ValueError:
            pytest.fail(f"Could not parse PCA coordinates as floats for run_id {row[0]}")
    return coords


def assert_matches_recomputed_pca(coords, expected):
    # PCA component signs are mathematically arbitrary, but components may not
    # be translated, reordered, or arbitrarily rotated.
    for component in range(2):
        positive_error = max(abs(coords[i][component] - expected[i][component]) for i in range(len(coords)))
        negative_error = max(abs(coords[i][component] + expected[i][component]) for i in range(len(coords)))
        assert min(positive_error, negative_error) <= 5.1e-5, (
            f"pca_{component + 1} does not match the recomputed standardized PCA component."
        )


def test_artifacts_dir_and_csv_exist():
    assert os.path.exists("/home/user/artifacts"), "The artifacts directory does not exist."
    assert os.path.isfile(CSV_PATH), f"The output file {CSV_PATH} does not exist."


def test_csv_structure_and_sorting():
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["run_id", "pca_1", "pca_2"], f"Expected header ['run_id', 'pca_1', 'pca_2'], but got {header}"
        rows = list(reader)
        assert len(rows) == 5, f"Expected 5 rows of data, but got {len(rows)}"
        run_ids = [row[0] for row in rows]
        expected_run_ids = ["run_A", "run_B", "run_C", "run_D", "run_E"]
        assert run_ids == expected_run_ids, f"Expected run_ids to be sorted as {expected_run_ids}, but got {run_ids}"


def test_pca_coordinates_distances():
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        coords = []
        for row in reader:
            try:
                pca_1 = float(row["pca_1"])
                pca_2 = float(row["pca_2"])
                coords.append((pca_1, pca_2))
            except ValueError:
                pytest.fail(f"Could not parse PCA coordinates as floats for run_id {row.get('run_id')}")

    expected_distances = [
        [0.0, 1.2599, 3.2514, 1.4878, 4.4568],
        [1.2599, 0.0, 1.9962, 2.7317, 3.2104],
        [3.2514, 1.9962, 0.0, 4.7001, 1.2185],
        [1.4878, 2.7317, 4.7001, 0.0, 5.9181],
        [4.4568, 3.2104, 1.2185, 5.9181, 0.0],
    ]
    for i in range(len(coords)):
        for j in range(len(coords)):
            dist = math.hypot(coords[i][0] - coords[j][0], coords[i][1] - coords[j][1])
            expected_dist = expected_distances[i][j]
            assert abs(dist - expected_dist) < 0.01, (
                f"Distance between point {i} and {j} is {dist:.4f}, expected {expected_dist:.4f}. "
                "PCA results do not match expected projection."
            )


def test_recomputed_ordered_pca_and_four_decimal_format():
    expected_ids, expected = expected_projection()
    coords = read_and_validate_csv(expected_ids)
    assert_matches_recomputed_pca(coords, expected)


def test_z_script_uses_raw_logs_and_recomputes_output():
    target = os.path.join(RAW_DIR, "run_A.json")
    with open(target, "rb") as f:
        original = f.read()
    try:
        doc = json.loads(original.decode("utf-8"))
        doc["metrics"]["loss"] += 0.137
        doc["metrics"]["epoch_time"] += 1.75
        doc["metrics"]["cpu_load"] -= 6.25
        with open(target, "w") as f:
            json.dump(doc, f)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        subprocess.run(["python3", SCRIPT_PATH], check=True, timeout=120)
        expected_ids, expected = expected_projection()
        coords = read_and_validate_csv(expected_ids)
        assert_matches_recomputed_pca(coords, expected)
    finally:
        with open(target, "wb") as f:
            f.write(original)
        subprocess.run(["python3", SCRIPT_PATH], check=True, timeout=120)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
