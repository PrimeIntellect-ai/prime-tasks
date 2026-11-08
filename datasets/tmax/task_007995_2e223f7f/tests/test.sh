#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess

SOURCE_PATH = "/home/user/evaluate.c"
CSV_PATH = "/home/user/predictions.csv"
LOG_PATH = "/home/user/best_model.log"
EXECUTABLE_PATH = "/tmp/evaluate_verified"


def assert_log(expected_alpha, expected_mse):
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} does not exist. Did you run your compiled C program?"

    with open(LOG_PATH, "r") as f:
        content = f.read().strip().split("\n")

    assert len(content) == 2, f"Expected exactly 2 lines in {LOG_PATH}, found {len(content)} lines."

    expected_line_1 = f"Best Alpha: {expected_alpha:.2f}"
    expected_line_2 = f"Lowest MSE: {expected_mse:.4f}"
    assert content[0].strip() == expected_line_1, f"Expected first line to be '{expected_line_1}', but got '{content[0]}'."
    assert content[1].strip() == expected_line_2, f"Expected second line to be '{expected_line_2}', but got '{content[1]}'."


def expected_from_rows(rows):
    totals = {}
    counts = {}
    for _, _, alpha, y_true, y_pred in rows:
        alpha = float(alpha)
        error = float(y_true) - float(y_pred)
        totals[alpha] = totals.get(alpha, 0.0) + error * error
        counts[alpha] = counts.get(alpha, 0) + 1

    mses = {alpha: totals[alpha] / counts[alpha] for alpha in totals}
    best_alpha = min(mses, key=mses.get)
    return best_alpha, mses[best_alpha]


def write_rows(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["run_id", "fold", "alpha", "y_true", "y_pred"])
        writer.writerows(rows)


def execute_and_check(rows):
    write_rows(rows)
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    subprocess.run([EXECUTABLE_PATH], cwd="/home/user", check=True, timeout=10)
    expected_alpha, expected_mse = expected_from_rows(rows)
    assert_log(expected_alpha, expected_mse)


def make_random_case():
    rng = random.Random(secrets.randbits(128))
    alphas = rng.sample([x / 100.0 for x in range(7, 296)], 4)
    rng.shuffle(alphas)
    scales = [0.035, 0.13, 0.27, 0.43]
    rng.shuffle(scales)

    rows = []
    run_id = rng.randint(100, 10000)
    for alpha, scale in zip(alphas, scales):
        count = rng.randint(8, 17)
        for i in range(count):
            fold = (i % 5) + 1
            y_true = rng.uniform(-4.0, 7.0)
            factor = rng.uniform(0.65, 1.35)
            sign = -1.0 if rng.randrange(2) else 1.0
            y_pred = y_true + sign * scale * factor
            rows.append([run_id, fold, f"{alpha:.2f}", f"{y_true:.8f}", f"{y_pred:.8f}"])
        run_id += rng.randint(1, 9)

    rng.shuffle(rows)
    return rows


def test_submission():
    assert os.path.isfile(SOURCE_PATH), f"The C source file {SOURCE_PATH} does not exist. Did you write the program?"

    # Preserve the original verifier's assertions about the artifact produced by the agent.
    assert_log(0.50, 0.0150)

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    try:
        subprocess.run(
            ["gcc", "-O2", SOURCE_PATH, "-o", EXECUTABLE_PATH, "-lm"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)

        # First execute against the supplied data and derive its answer independently.
        with open(CSV_PATH, newline="") as f:
            supplied_rows = list(csv.reader(f))[1:]
        execute_and_check(supplied_rows)

        # Unpredictable cases ensure the program really parses and aggregates the CSV.
        execute_and_check(make_random_case())
        execute_and_check(make_random_case())
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        if os.path.exists(EXECUTABLE_PATH):
            os.remove(EXECUTABLE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
