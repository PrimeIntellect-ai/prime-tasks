#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
REPORT_PATH = "/home/user/report.json"
DATA_DIR = "/home/user/data"
SOURCE1_PATH = os.path.join(DATA_DIR, "source1.csv")
SOURCE2_PATH = os.path.join(DATA_DIR, "source2.csv")
META_PATH = os.path.join(DATA_DIR, "meta.csv")


def compute_expected_metrics():
    meta = {}
    if os.path.exists(META_PATH):
        with open(META_PATH, "r", encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                meta[row["item_id"]] = row["category_code"]

    combined = []
    if os.path.exists(SOURCE1_PATH):
        with open(SOURCE1_PATH, "r", encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                combined.append({"id": row["id"], "text": row["text"]})

    if os.path.exists(SOURCE2_PATH):
        with open(SOURCE2_PATH, "r", encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                combined.append({"id": row["req_id"], "text": row["review_body"]})

    total_rows = 0
    sum_scores = 0
    for row in combined:
        if row["id"] not in meta:
            continue
        text = row["text"].lower()
        text = re.sub(r"[^a-z0-9\s]", "", text)
        tokens = text.split()
        token_count = len([token for token in tokens if len(token) >= 3])
        score = (token_count * len(meta[row["id"]])) % 10
        total_rows += 1
        sum_scores += score

    return total_rows, sum_scores


def write_csv(path, fieldnames, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def run_pipeline_and_validate(expected_total_rows, expected_sum_scores):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"pipeline.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing after pipeline execution."

    try:
        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {REPORT_PATH} is not valid JSON: {exc}")

    assert "total_rows" in data, "Key 'total_rows' is missing from report.json."
    assert "sum_scores" in data, "Key 'sum_scores' is missing from report.json."
    assert "benchmark_runs" in data, "Key 'benchmark_runs' is missing from report.json."
    assert set(data) == {"total_rows", "sum_scores", "benchmark_runs"}, "report.json does not have the exact required schema."
    assert data["total_rows"] == expected_total_rows, (
        f"Expected total_rows to be {expected_total_rows}, got {data['total_rows']}"
    )
    assert data["sum_scores"] == expected_sum_scores, (
        f"Expected sum_scores to be {expected_sum_scores}, got {data['sum_scores']}"
    )
    assert data["benchmark_runs"] == 100, (
        f"Expected benchmark_runs to be 100, got {data['benchmark_runs']}"
    )
    return data


def make_dynamic_fixture(rng, trial):
    base = rng.randrange(2_000_000, 8_000_000) + trial * 100
    matched_count = rng.randrange(3, 8)
    source1 = []
    source2 = []
    meta = []

    for index in range(matched_count):
        item_id = str(base + index)
        valid_count = rng.randrange(1, 9)
        valid_tokens = [f"Token{index}{n}" for n in range(valid_count)]
        # Punctuation is deliberately attached so it must be removed rather than
        # treated as a source column delimiter or retained in token lengths.
        text = "AA ! " + ", ".join(valid_tokens) + " short-word. x 12"
        category_code = "C" * rng.randrange(1, 9)
        meta.append({"item_id": item_id, "category_code": category_code})

        if index % 2 == 0:
            source1.append({"id": item_id, "text": text, "date": f"2026-01-{index + 1:02d}"})
        else:
            source2.append({"req_id": item_id, "review_body": text, "timestamp": str(1800000000 + index)})

    # Each source also contains a row that must be dropped by the inner join.
    source1.append({"id": str(base + 80), "text": "unmatched source one words", "date": "2026-02-01"})
    source2.append({"req_id": str(base + 81), "review_body": "unmatched source two words", "timestamp": "1800000999"})

    write_csv(SOURCE1_PATH, ["id", "text", "date"], source1)
    write_csv(SOURCE2_PATH, ["req_id", "review_body", "timestamp"], source2)
    write_csv(META_PATH, ["item_id", "category_code"], meta)


def test_pipeline_script_exists_executable_and_processes_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"Master execution script {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    backup_dir = tempfile.mkdtemp(prefix="pipeline-verifier-")
    original_report = None
    try:
        for path in (SOURCE1_PATH, SOURCE2_PATH, META_PATH):
            shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))

        # First retain the original verifier's assertions, but require the agent's
        # executable to generate a fresh report rather than accepting stale output.
        original_expected = compute_expected_metrics()
        original_data = run_pipeline_and_validate(*original_expected)
        original_report = json.dumps(original_data, indent=2) + "\n"

        # Then replace all inputs with unpredictable fixtures and execute again.
        # This rejects fixed/prewritten reports and exercises both source mappings,
        # the metadata join, tokenization, scoring, and unmatched-row removal.
        rng = random.SystemRandom()
        previous_result = original_expected
        for trial in range(2):
            for _ in range(20):
                make_dynamic_fixture(rng, trial)
                expected = compute_expected_metrics()
                if expected != previous_result:
                    break
            else:
                pytest.fail("Could not construct a distinct dynamic fixture.")
            run_pipeline_and_validate(*expected)
            previous_result = expected
    finally:
        for name in ("source1.csv", "source2.csv", "meta.csv"):
            saved = os.path.join(backup_dir, name)
            if os.path.exists(saved):
                shutil.copy2(saved, os.path.join(DATA_DIR, name))
        if original_report is not None:
            with open(REPORT_PATH, "w", encoding="utf-8") as f:
                f.write(original_report)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
