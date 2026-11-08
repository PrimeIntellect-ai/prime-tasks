#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/evaluate_experiments.sh"
BASELINE_PATH = "/home/user/baseline.csv"
NEW_MODEL_PATH = "/home/user/new_model.csv"
REPORT_PATH = "/home/user/experiment_report.txt"
HEADER = ["id", "true_label", "pred_label", "pca1", "pca2"]


def run_script(baseline, new_model):
    return subprocess.run(
        [SCRIPT_PATH, baseline, new_model],
        capture_output=True,
        text=True,
        timeout=10,
    )


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(HEADER)
        writer.writerows(rows)


def expected_report(baseline_rows, new_rows):
    baseline_accuracy = sum(row[1] == row[2] for row in baseline_rows) / len(baseline_rows)
    new_accuracy = sum(row[1] == row[2] for row in new_rows) / len(new_rows)
    se = math.sqrt(baseline_accuracy * (1.0 - baseline_accuracy) / len(baseline_rows))
    lower = baseline_accuracy - 1.96 * se
    upper = baseline_accuracy + 1.96 * se
    return (
        f"Baseline Accuracy: {baseline_accuracy:.4f}\n"
        f"Baseline CI: [{lower:.4f}, {upper:.4f}]\n"
        f"New Model Accuracy: {new_accuracy:.4f}"
    )


def make_random_case(rng):
    n = rng.randint(9, 37)
    ids = rng.sample(range(1000, 1000000), n)
    true_labels = [rng.randint(0, 1) for _ in range(n)]

    baseline_correct = rng.randint(1, n - 1)
    new_correct = rng.randint(1, n - 1)
    baseline_flags = [True] * baseline_correct + [False] * (n - baseline_correct)
    new_flags = [True] * new_correct + [False] * (n - new_correct)
    rng.shuffle(baseline_flags)
    rng.shuffle(new_flags)

    baseline_rows = []
    new_rows = []
    for i in range(n):
        label = true_labels[i]
        pca1 = f"{rng.uniform(-8, 8):.7f}"
        pca2 = f"{rng.uniform(-8, 8):.7f}"
        baseline_pred = label if baseline_flags[i] else 1 - label
        new_pred = label if new_flags[i] else 1 - label
        baseline_rows.append([str(ids[i]), str(label), str(baseline_pred), pca1, pca2])
        new_rows.append([str(ids[i]), str(label), str(new_pred), pca1, pca2])

    # Correspondence is by ID, so independently ordered files must still pass.
    rng.shuffle(baseline_rows)
    rng.shuffle(new_rows)
    return baseline_rows, new_rows


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_script_success_and_report_content():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = run_script(BASELINE_PATH, NEW_MODEL_PATH)

    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    assert os.path.exists(REPORT_PATH), f"Report file not created at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        report_content = f.read().strip()

    expected_content = (
        "Baseline Accuracy: 0.8000\n"
        "Baseline CI: [0.5521, 1.0479]\n"
        "New Model Accuracy: 1.0000"
    )
    assert report_content == expected_content, (
        f"Report content mismatch.\nExpected:\n{expected_content}\nGot:\n{report_content}"
    )


def test_script_reproducibility_error():
    bad_model_content = """id,true_label,pred_label,pca1,pca2
1,1,1,0.5,0.1
2,0,0,0.2,0.999
3,1,1,0.8,0.3
4,0,0,0.1,0.4
5,1,1,0.9,0.2
6,0,0,0.3,0.3
7,1,1,0.4,0.4
8,0,0,0.5,0.5
9,1,1,0.6,0.6
10,0,0,0.7,0.7
"""
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write(bad_model_content)
        bad_model_path = tmp.name

    try:
        result = run_script(BASELINE_PATH, bad_model_path)
        assert result.returncode == 1, (
            f"Expected return code 1 for reproducibility error, got {result.returncode}"
        )
        assert result.stdout.strip() == "Reproducibility Error", (
            f"Expected stdout 'Reproducibility Error', got '{result.stdout.strip()}'"
        )
    finally:
        os.remove(bad_model_path)


def test_randomized_metrics_and_id_matching():
    rng = random.Random(secrets.randbits(128))
    for _ in range(5):
        baseline_rows, new_rows = make_random_case(rng)
        with tempfile.TemporaryDirectory() as directory:
            baseline_path = os.path.join(directory, "baseline.csv")
            new_path = os.path.join(directory, "new.csv")
            write_csv(baseline_path, baseline_rows)
            write_csv(new_path, new_rows)

            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
            result = run_script(baseline_path, new_path)

            assert result.returncode == 0, (
                f"Random valid case failed with {result.returncode}; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert os.path.isfile(REPORT_PATH), "Random valid case did not create report"
            with open(REPORT_PATH, "r") as f:
                actual = f.read().strip()
            expected = expected_report(baseline_rows, new_rows)
            assert actual == expected, f"Expected:\n{expected}\nGot:\n{actual}"


def test_randomized_reproducibility_drift():
    rng = random.Random(secrets.randbits(128))
    for _ in range(4):
        baseline_rows, new_rows = make_random_case(rng)
        changed_index = rng.randrange(len(new_rows))
        changed_column = rng.choice([3, 4])
        old_value = new_rows[changed_index][changed_column]
        new_rows[changed_index][changed_column] = f"{float(old_value) + rng.uniform(0.01, 2.0):.9f}"

        with tempfile.TemporaryDirectory() as directory:
            baseline_path = os.path.join(directory, "baseline.csv")
            new_path = os.path.join(directory, "drifted.csv")
            write_csv(baseline_path, baseline_rows)
            write_csv(new_path, new_rows)
            result = run_script(baseline_path, new_path)

        assert result.returncode == 1, (
            f"Expected return code 1 for randomized PCA drift, got {result.returncode}"
        )
        assert result.stdout.strip() == "Reproducibility Error", (
            f"Expected exact reproducibility message, got {result.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
