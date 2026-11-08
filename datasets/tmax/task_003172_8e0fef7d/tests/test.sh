#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import stat
import subprocess

HOME = "/home/user"
DATA_A = os.path.join(HOME, "data_a.csv")
DATA_B = os.path.join(HOME, "data_b.csv")
RESULTS = os.path.join(HOME, "results.json")
ANALYZE = os.path.join(HOME, "analyze.go")


def compute_expected(data_a_path=DATA_A, data_b_path=DATA_B):
    with open(data_a_path, "r", newline="") as f:
        data_a = {row["id"]: row for row in csv.DictReader(f)}
    with open(data_b_path, "r", newline="") as f:
        data_b = {row["id"]: row for row in csv.DictReader(f)}

    merged = []
    for id_val, row_a in data_a.items():
        if id_val in data_b:
            merged_row = {**row_a, **data_b[id_val]}
            if any(v == "NA" or v == "" for v in merged_row.values()):
                continue
            merged_row["id"] = int(merged_row["id"])
            for key in ["f1", "f2", "f3", "f4", "y"]:
                merged_row[key] = float(merged_row[key])
            merged.append(merged_row)

    merged.sort(key=lambda row: row["id"])
    train_size = (len(merged) * 80) // 100
    train = merged[:train_size]
    test = merged[train_size:]

    def mean(values):
        return sum(values) / len(values)

    def corr(xs, ys):
        mx = mean(xs)
        my = mean(ys)
        covariance = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        variance_x = sum((x - mx) ** 2 for x in xs)
        variance_y = sum((y - my) ** 2 for y in ys)
        if variance_x == 0 or variance_y == 0:
            return 0
        return covariance / math.sqrt(variance_x * variance_y)

    features = ["f1", "f2", "f3", "f4"]
    y_train = [row["y"] for row in train]
    correlations = {
        feature: corr([row[feature] for row in train], y_train)
        for feature in features
    }
    best_feature = max(correlations, key=lambda key: abs(correlations[key]))

    x_train = [row[best_feature] for row in train]
    mx = mean(x_train)
    my = mean(y_train)
    covariance = sum((x - mx) * (y - my) for x, y in zip(x_train, y_train))
    variance_x = sum((x - mx) ** 2 for x in x_train)
    slope = covariance / variance_x
    intercept = my - slope * mx

    predictions = [slope * row[best_feature] + intercept for row in test]
    mse = mean([(row["y"] - prediction) ** 2 for row, prediction in zip(test, predictions)])

    return {
        "selected_feature": best_feature,
        "slope": round(slope, 4),
        "intercept": round(intercept, 4),
        "test_mse": round(mse, 4),
    }, merged, correlations


def run_program():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        ["go", "run", "analyze.go"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert completed.returncode == 0, "go run analyze.go failed:\n" + completed.stdout
    assert os.path.isfile(RESULTS), "The Go program did not generate /home/user/results.json"


def assert_results(expected):
    with open(RESULTS, "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{RESULTS} is not valid JSON."

    assert "selected_feature" in actual, "Key 'selected_feature' missing in results.json"
    assert "slope" in actual, "Key 'slope' missing in results.json"
    assert "intercept" in actual, "Key 'intercept' missing in results.json"
    assert "test_mse" in actual, "Key 'test_mse' missing in results.json"

    assert actual["selected_feature"] == expected["selected_feature"], \
        f"Expected feature {expected['selected_feature']}, got {actual['selected_feature']}"
    assert math.isclose(actual["slope"], expected["slope"], abs_tol=1e-3), \
        f"Expected slope {expected['slope']}, got {actual['slope']}"
    assert math.isclose(actual["intercept"], expected["intercept"], abs_tol=1e-3), \
        f"Expected intercept {expected['intercept']}, got {actual['intercept']}"
    assert math.isclose(actual["test_mse"], expected["test_mse"], abs_tol=1e-3), \
        f"Expected test_mse {expected['test_mse']}, got {actual['test_mse']}"


def test_go_module_exists():
    go_mod_path = os.path.join(HOME, "go.mod")
    assert os.path.isfile(go_mod_path), "Go module was not initialized (go.mod is missing)."
    with open(go_mod_path, "r") as f:
        content = f.read()
    assert "module ml_task" in content, "Go module name is not 'ml_task'."


def test_results_json():
    assert os.path.lexists(ANALYZE), f"File {ANALYZE} is missing."
    assert stat.S_ISREG(os.lstat(ANALYZE).st_mode), f"{ANALYZE} must be a regular Go source file."

    with open(DATA_A, "rb") as f:
        original_a = f.read()
    with open(DATA_B, "rb") as f:
        original_b = f.read()
    original_result = None
    if os.path.isfile(RESULTS):
        with open(RESULTS, "rb") as f:
            original_result = f.read()

    try:
        # Execute the submitted program on the supplied datasets and retain the
        # original verifier's numerical assertions.
        expected, _, _ = compute_expected()
        run_program()
        assert_results(expected)

        # Exercise the same artifact on an unpredictable dataset. The training
        # rows make f3 best, while test-only information makes f4 appear best on
        # the full dataset, detecting hard-coded output and leakage in selection.
        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        rows_a = []
        rows_b = []
        for identifier in range(1, 21):
            if identifier <= 16:
                y = rng.uniform(10.0, 70.0)
                f3 = 1.7 * y + rng.uniform(-0.08, 0.08)
                f4 = rng.uniform(-20.0, 20.0)
            else:
                y = rng.uniform(500.0, 900.0)
                f3 = rng.uniform(20.0, 100.0)
                f4 = y * 100.0 + rng.uniform(-0.1, 0.1)
            rows_a.append({
                "id": str(identifier),
                "f1": f"{rng.uniform(-50.0, 50.0):.8f}",
                "f2": f"{rng.uniform(-50.0, 50.0):.8f}",
                "y": f"{y:.8f}",
            })
            rows_b.append({
                "id": str(identifier),
                "f3": f"{f3:.8f}",
                "f4": f"{f4:.8f}",
            })

        # Rows that must be discarded, plus unmatched rows, exercise joining and cleaning.
        rows_a.extend([
            {"id": "21", "f1": "NA", "f2": "2.0", "y": "3.0"},
            {"id": "22", "f1": "1.0", "f2": "2.0", "y": "3.0"},
            {"id": "99", "f1": "1.0", "f2": "2.0", "y": "3.0"},
        ])
        rows_b.extend([
            {"id": "21", "f3": "4.0", "f4": "5.0"},
            {"id": "22", "f3": "4.0", "f4": ""},
            {"id": "100", "f3": "4.0", "f4": "5.0"},
        ])
        rng.shuffle(rows_a)
        rng.shuffle(rows_b)

        with open(DATA_A, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["id", "f1", "f2", "y"])
            writer.writeheader()
            writer.writerows(rows_a)
        with open(DATA_B, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["id", "f3", "f4"])
            writer.writeheader()
            writer.writerows(rows_b)

        dynamic_expected, merged, train_correlations = compute_expected()
        assert dynamic_expected["selected_feature"] == "f3"

        def correlation(xs, ys):
            mx = sum(xs) / len(xs)
            my = sum(ys) / len(ys)
            numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
            denominator = math.sqrt(
                sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys)
            )
            return numerator / denominator if denominator else 0

        full_correlations = {
            feature: correlation([row[feature] for row in merged], [row["y"] for row in merged])
            for feature in ["f1", "f2", "f3", "f4"]
        }
        full_best = max(full_correlations, key=lambda key: abs(full_correlations[key]))
        assert full_best == "f4" and full_best != dynamic_expected["selected_feature"]
        assert max(train_correlations, key=lambda key: abs(train_correlations[key])) == "f3"

        run_program()
        assert_results(dynamic_expected)
    finally:
        with open(DATA_A, "wb") as f:
            f.write(original_a)
        with open(DATA_B, "wb") as f:
            f.write(original_b)
        if original_result is None:
            if os.path.exists(RESULTS):
                os.remove(RESULTS)
        else:
            with open(RESULTS, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
