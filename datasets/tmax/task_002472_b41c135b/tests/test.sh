#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import subprocess

SOURCE = "/home/user/pipeline.cpp"
DATASET = "/home/user/dataset.csv"
RESULTS = "/home/user/results.json"
BINARY = "/tmp/pipeline_verifier_bin"


def load_results():
    assert os.path.isfile(RESULTS), f"File {RESULTS} does not exist. The pipeline may not have run successfully."
    with open(RESULTS, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULTS} is not valid JSON."

    expected_keys = [
        "imputed_feature_x_median",
        "t_statistic",
        "regression_slope",
        "regression_intercept",
    ]
    for key in expected_keys:
        assert key in results, f"Key '{key}' is missing from {RESULTS}."
    return results


def run_pipeline():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert completed.returncode == 0, (
        f"Compiled pipeline exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    return load_results()


def expected_for(rows):
    valid_x = sorted(int(row[1]) for row in rows if row[1] != "")
    assert valid_x
    n = len(valid_x)
    if n % 2:
        median = valid_x[n // 2]
    else:
        median = math.floor((valid_x[n // 2 - 1] + valid_x[n // 2]) / 2.0)

    x = [median if row[1] == "" else int(row[1]) for row in rows]
    y = [float(row[2]) for row in rows]
    y0 = [float(row[2]) for row in rows if int(row[0]) == 0]
    y1 = [float(row[2]) for row in rows if int(row[0]) == 1]

    mean0 = sum(y0) / len(y0)
    mean1 = sum(y1) / len(y1)
    var0 = sum((v - mean0) ** 2 for v in y0) / (len(y0) - 1)
    var1 = sum((v - mean1) ** 2 for v in y1) / (len(y1) - 1)
    pooled = ((len(y0) - 1) * var0 + (len(y1) - 1) * var1) / (len(y0) + len(y1) - 2)
    t_stat = (mean0 - mean1) / math.sqrt(pooled * (1.0 / len(y0) + 1.0 / len(y1)))

    mean_x = sum(x) / len(x)
    mean_y = sum(y) / len(y)
    slope = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y)) / sum((a - mean_x) ** 2 for a in x)
    intercept = mean_y - slope * mean_x

    return {
        "imputed_feature_x_median": median,
        "t_statistic": round(t_stat, 4),
        "regression_slope": round(slope, 4),
        "regression_intercept": round(intercept, 4),
    }


def write_dataset(rows):
    with open(DATASET, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["group", "feature_x", "target_y"])
        writer.writerows(rows)


def assert_dynamic_results(actual, expected):
    assert actual["imputed_feature_x_median"] == expected["imputed_feature_x_median"]
    for key in ("t_statistic", "regression_slope", "regression_intercept"):
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool), f"{key} must be a number"
        assert math.isfinite(actual[key]), f"{key} must be finite"
        assert math.isclose(actual[key], expected[key], abs_tol=0.000051), (
            f"Expected {key} to round to {expected[key]}, got {actual[key]}"
        )


def test_pipeline_source_and_behavior():
    assert os.path.isfile(SOURCE), f"Required source file {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"Required source file {SOURCE} is empty."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY, "-larmadillo"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert compile_result.returncode == 0, f"pipeline.cpp failed to compile: {compile_result.stderr}"

    backup = "/tmp/original_dataset_verifier.csv"
    shutil.copyfile(DATASET, backup)
    try:
        # Execute the submitted program on the supplied dataset, then retain all
        # assertions from the original verifier.
        results = run_pipeline()
        assert results["imputed_feature_x_median"] == 60, (
            f"Expected imputed_feature_x_median to be 60, got {results['imputed_feature_x_median']}"
        )
        t_stat = results["t_statistic"]
        assert isinstance(t_stat, (int, float)), "t_statistic must be a number"
        assert math.isclose(t_stat, 1.7645, abs_tol=0.005), f"Expected t_statistic to be approx 1.7645, got {t_stat}"
        slope = results["regression_slope"]
        assert isinstance(slope, (int, float)), "regression_slope must be a number"
        assert math.isclose(slope, 2.3787, abs_tol=0.005), f"Expected regression_slope to be approx 2.3787, got {slope}"
        intercept = results["regression_intercept"]
        assert isinstance(intercept, (int, float)), "regression_intercept must be a number"
        assert math.isclose(intercept, 17.4363, abs_tol=0.005), f"Expected regression_intercept to be approx 17.4363, got {intercept}"

        datasets = [
            [
                (0, "1", "10.0"),
                (0, "", "12.0"),
                (0, "5", "14.0"),
                (1, "9", "20.0"),
                (1, "", "23.0"),
                (1, "13", "26.0"),
            ],
            [
                (0, "", "3.2"),
                (1, "2", "6.5"),
                (0, "4", "8.1"),
                (1, "", "9.9"),
                (0, "10", "12.7"),
                (1, "12", "15.2"),
                (0, "20", "17.4"),
                (1, "", "22.8"),
            ],
        ]
        for rows in datasets:
            write_dataset(rows)
            assert_dynamic_results(run_pipeline(), expected_for(rows))
    finally:
        shutil.copyfile(backup, DATASET)
        if os.path.exists(BINARY):
            try:
                if os.path.exists(RESULTS):
                    os.remove(RESULTS)
                subprocess.run([BINARY], cwd="/home/user", timeout=20, check=False)
            except Exception:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
