#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import secrets
import subprocess

SCRIPT_PATH = "/home/user/process_artifacts.sh"
LOG_PATH = "/home/user/raw_experiments.log"
CSV_PATH = "/home/user/posterior_metrics.csv"


def compute_expected(log_text):
    models = {}
    reader = csv.DictReader(io.StringIO(log_text), delimiter="|")
    for row in reader:
        exec_time = row["exec_time_sec"].strip()
        if not exec_time:
            continue
        exec_time = float(exec_time)
        if exec_time < 0 or exec_time > 3600:
            continue

        successes_str = row["successes"].strip()
        if not successes_str:
            continue
        successes = int(successes_str)

        trials_str = row["trials"].strip()
        trials = 1000 if not trials_str else int(trials_str)
        if successes > trials:
            continue

        model_name = row["model_name"].strip()
        if model_name not in models:
            models[model_name] = {"successes": 0, "failures": 0}
        models[model_name]["successes"] += successes
        models[model_name]["failures"] += trials - successes

    expected_rows = []
    for model_name in sorted(models):
        alpha_post = 1 + models[model_name]["successes"]
        beta_post = 1 + models[model_name]["failures"]
        expected_rows.append({
            "model_name": model_name,
            "alpha": str(alpha_post),
            "beta": str(beta_post),
            "expected_value": f"{alpha_post / (alpha_post + beta_post):.4f}",
        })
    return expected_rows


def check_output(expected_rows):
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} is missing."
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["model_name", "alpha", "beta", "expected_value"], \
            f"CSV header is incorrect. Expected ['model_name', 'alpha', 'beta', 'expected_value'], got {reader.fieldnames}"
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in CSV, got {len(actual_rows)}."
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual["model_name"] == expected["model_name"], \
            f"Row {i+1}: expected model_name {expected['model_name']}, got {actual['model_name']}"
        assert actual["alpha"] == expected["alpha"], \
            f"Row {i+1} ({actual['model_name']}): expected alpha {expected['alpha']}, got {actual['alpha']}"
        assert actual["beta"] == expected["beta"], \
            f"Row {i+1} ({actual['model_name']}): expected beta {expected['beta']}, got {actual['beta']}"
        assert actual["expected_value"] == expected["expected_value"], \
            f"Row {i+1} ({actual['model_name']}): expected expected_value {expected['expected_value']}, got {actual['expected_value']}"


def run_case(log_text):
    with open(LOG_PATH, "w", newline="") as f:
        f.write(log_text)
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, \
        f"Script failed with exit code {result.returncode}. stdout: {result.stdout!r} stderr: {result.stderr!r}"
    check_output(compute_expected(log_text))


def make_random_case():
    suffix = secrets.token_hex(5)
    names = [f"ModelA_{suffix}", f"ModelB_{suffix}", f"ModelC_{suffix}"]
    successes_a1 = secrets.randbelow(300) + 1
    trials_a1 = secrets.randbelow(300) + 301
    successes_a2 = secrets.randbelow(300) + 700
    successes_b = secrets.randbelow(101)
    trials_b = secrets.randbelow(101) + 100
    trials_c = secrets.randbelow(300) + 1

    rows = [
        ["R01", names[0], str(successes_a1), str(trials_a1), "0"],
        ["R02", names[0], str(successes_a2), "", "3600"],
        ["R03", names[1], str(successes_b), str(trials_b), "25"],
        ["R04", names[2], str(trials_c), str(trials_c), "120"],
        ["R05", names[0], "10", "20", "-1"],
        ["R06", names[1], "10", "20", "3601"],
        ["R07", names[2], "51", "50", "100"],
        ["R08", names[1], "", "500", "100"],
    ]
    random.SystemRandom().shuffle(rows)
    out = io.StringIO()
    writer = csv.writer(out, delimiter="|", lineterminator="\n")
    writer.writerow(["experiment_id", "model_name", "successes", "trials", "exec_time_sec"])
    writer.writerows(rows)
    return out.getvalue()


def test_script_and_pipeline():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    assert os.path.isfile(LOG_PATH), f"Raw log {LOG_PATH} is missing."
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} is missing."

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        run_case(original_log.decode())
        for _ in range(3):
            run_case(make_random_case())
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
