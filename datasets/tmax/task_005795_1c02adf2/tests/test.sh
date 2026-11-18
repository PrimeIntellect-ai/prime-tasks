#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import secrets
import subprocess
import tempfile


def expected_results(records):
    train = records[:6]
    tests = records[6:]

    mean = sum(feature for _, feature, _ in train) / len(train)
    variance = sum((feature - mean) ** 2 for _, feature, _ in train) / len(train)
    stddev = math.sqrt(variance)

    train_z = [((feature - mean) / stddev, label) for _, feature, label in train]
    z_0 = [z for z, label in train_z if label == 0]
    z_1 = [z for z, label in train_z if label != 0]

    mu_0 = sum(z_0) / len(z_0)
    var_0 = sum((z - mu_0) ** 2 for z in z_0) / len(z_0)
    mu_1 = sum(z_1) / len(z_1)
    var_1 = sum((z - mu_1) ** 2 for z in z_1) / len(z_1)

    expected = {}
    for id_, feature, _ in tests:
        z = (feature - mean) / stddev
        p0 = math.exp(-((z - mu_0) ** 2) / (2 * var_0)) / math.sqrt(2 * math.pi * var_0)
        p1 = math.exp(-((z - mu_1) ** 2) / (2 * var_1)) / math.sqrt(2 * math.pi * var_1)
        expected[id_] = (z, 1 if p1 > p0 else 0)
    return expected


def validate_predictions(path, records):
    expected = expected_results(records)
    expected_ids = [id_ for id_, _, _ in records[6:]]

    assert os.path.isfile(path), f"{path} was not produced"
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "z_score", "predicted_label"], \
            f"Unexpected CSV header: {reader.fieldnames}"
        rows = list(reader)

    assert len(rows) == 4, f"Expected 4 rows in predictions.csv, got {len(rows)}"
    actual_ids = [int(row["id"]) for row in rows]
    assert actual_ids == expected_ids, \
        f"Expected test IDs exactly once in order {expected_ids}, got {actual_ids}"

    for row in rows:
        id_ = int(row["id"])
        z_score = float(row["z_score"])
        pred = int(row["predicted_label"])
        expected_z, expected_pred = expected[id_]
        assert math.isclose(z_score, expected_z, abs_tol=1e-5), \
            f"For id {id_}, expected z_score ~{expected_z:.6f}, got {z_score}"
        assert pred == expected_pred, \
            f"For id {id_}, expected predicted_label {expected_pred}, got {pred}"


def test_predictions_file_exists():
    assert os.path.isfile("/home/user/fixed_predictions.csv"), "/home/user/fixed_predictions.csv is missing. Did you compile, run, and rename the output file?"


def test_predictions_content():
    # Recompute the expected values based on the training set (first 6 rows)
    train_features = [2.0, 2.5, 3.0, 8.0, 8.5, 9.0]
    test_features = [(6, 2.2), (7, 8.8), (8, 5.0), (9, 5.6)]

    mean = sum(train_features) / len(train_features)
    variance = sum((x - mean) ** 2 for x in train_features) / len(train_features)
    stddev = math.sqrt(variance)
    expected_z_scores = {id_: (feat - mean) / stddev for id_, feat in test_features}

    train_z_scores = [(x - mean) / stddev for x in train_features]
    z_0 = train_z_scores[:3]
    z_1 = train_z_scores[3:]
    mu_0 = sum(z_0) / len(z_0)
    var_0 = sum((x - mu_0) ** 2 for x in z_0) / len(z_0)
    mu_1 = sum(z_1) / len(z_1)
    var_1 = sum((x - mu_1) ** 2 for x in z_1) / len(z_1)

    expected_preds = {}
    for id_, z in expected_z_scores.items():
        p0 = math.exp(-((z - mu_0) ** 2) / (2 * var_0)) / math.sqrt(2 * math.pi * var_0)
        p1 = math.exp(-((z - mu_1) ** 2) / (2 * var_1)) / math.sqrt(2 * math.pi * var_1)
        expected_preds[id_] = 1 if p1 > p0 else 0

    with open("/home/user/fixed_predictions.csv", "r") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 4, f"Expected 4 rows in predictions.csv, got {len(rows)}"
    actual_ids = [int(row["id"]) for row in rows]
    assert actual_ids == [6, 7, 8, 9], \
        f"Expected IDs 6, 7, 8, and 9 exactly once in order, got {actual_ids}"

    for row in rows:
        id_ = int(row["id"])
        z_score = float(row["z_score"])
        pred = int(row["predicted_label"])

        assert id_ in expected_z_scores, f"Unexpected id {id_} in predictions"
        expected_z = expected_z_scores[id_]
        assert math.isclose(z_score, expected_z, abs_tol=1e-5), f"For id {id_}, expected z_score ~{expected_z:.6f}, got {z_score}. The ETL data leakage bug might not be fully fixed."
        expected_pred = expected_preds[id_]
        assert pred == expected_pred, f"For id {id_}, expected predicted_label {expected_pred}, got {pred}."


def test_c_code_modifications():
    assert os.path.isfile("/home/user/pipeline.c"), "/home/user/pipeline.c is missing"
    with open("/home/user/pipeline.c", "r") as f:
        content = f.read()

    # The normalisation loop should still use TOTAL_SIZE
    assert "data[i].z_score = (data[i].feature - mean) / stddev;" in content, "The normalization assignment was unexpectedly altered."


def test_compiled_pipeline_behavior():
    executable = "/home/user/pipeline"
    assert os.path.isfile(executable), "/home/user/pipeline is missing"
    assert os.access(executable, os.X_OK), "/home/user/pipeline is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/pipeline is not a compiled ELF executable"

    rng = secrets.SystemRandom()
    base = rng.uniform(-50.0, 50.0)
    ids = list(range(rng.randrange(10000, 90000), rng.randrange(10000, 90000) + 10))
    # Correct the independently generated range start while retaining unpredictable IDs.
    id_base = rng.randrange(10000, 90000)
    ids = list(range(id_base, id_base + 10))
    values = [
        base + rng.uniform(-6.0, -4.0),
        base + rng.uniform(-3.0, -1.0),
        base + rng.uniform(0.5, 2.5),
        base + rng.uniform(8.0, 10.0),
        base + rng.uniform(11.0, 13.0),
        base + rng.uniform(14.0, 17.0),
        base + rng.uniform(-4.0, 1.0),
        base + rng.uniform(10.0, 16.0),
        base + rng.uniform(3.0, 7.0),
        base + rng.uniform(6.0, 10.0),
    ]
    # Use exactly the decimal values written to data.csv when deriving answers.
    values = [float(f"{value:.12f}") for value in values]
    labels = [0, 0, 0, 1, 1, 1, -1, -1, -1, -1]
    records = list(zip(ids, values, labels))

    data_path = "/home/user/data.csv"
    with open(data_path, "rb") as f:
        original_data = f.read()

    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "pipeline_rebuilt")
        subprocess.run(
            ["gcc", "/home/user/pipeline.c", "-lm", "-o", rebuilt],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )

        try:
            with open(data_path, "w") as f:
                f.write("id,feature,label\n")
                for id_, feature, label in records:
                    f.write(f"{id_},{feature:.12f},{label}\n")

            for name, program in (("submitted", executable), ("rebuilt", rebuilt)):
                run_dir = os.path.join(tempdir, name)
                os.mkdir(run_dir)
                subprocess.run(
                    [program], cwd=run_dir, check=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
                )
                validate_predictions(os.path.join(run_dir, "predictions.csv"), records)
        finally:
            with open(data_path, "wb") as f:
                f.write(original_data)

        original_records = [
            (0, 2.0, 0), (1, 2.5, 0), (2, 3.0, 0),
            (3, 8.0, 1), (4, 8.5, 1), (5, 9.0, 1),
            (6, 2.2, -1), (7, 8.8, -1), (8, 5.0, -1), (9, 5.6, -1),
        ]
        original_run = os.path.join(tempdir, "original")
        os.mkdir(original_run)
        subprocess.run(
            [executable], cwd=original_run, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        validate_predictions(os.path.join(original_run, "predictions.csv"), original_records)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
