#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

import emoji

HOME = "/home/user"
RAW = os.path.join(HOME, "reviews_raw.csv")
SCRIPTS = [
    os.path.join(HOME, "extract.py"),
    os.path.join(HOME, "aggregate.py"),
    os.path.join(HOME, "sort.py"),
    os.path.join(HOME, "pipeline.py"),
]
OUTPUTS = [
    os.path.join(HOME, "features.jsonl"),
    os.path.join(HOME, "aggregated.csv"),
    os.path.join(HOME, "final_metrics.csv"),
]
HEADERS = ["product_id", "total_upvotes", "total_emojis", "avg_char_count"]


def read_raw():
    with open(RAW, "r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def expected_features(raw_rows):
    result = []
    for row in raw_rows:
        text = row["text"]
        result.append({
            "review_id": row["review_id"],
            "product_id": row["product_id"],
            "upvotes": int(row["upvotes"]),
            "char_count": len(text),
            "emoji_count": len(emoji.emoji_list(text)),
            "has_latin": re.search(r"[A-Za-z]", text) is not None,
        })
    return result


def expected_aggregates(features):
    groups = defaultdict(list)
    for item in features:
        groups[item["product_id"]].append(item)

    result = []
    for product_id, items in groups.items():
        result.append({
            "product_id": product_id,
            "total_upvotes": sum(x["upvotes"] for x in items),
            "total_emojis": sum(x["emoji_count"] for x in items),
            "avg_char_count": f'{sum(x["char_count"] for x in items) / len(items):.2f}',
        })
    return result


def sorted_aggregates(aggregates):
    return sorted(
        aggregates,
        key=lambda x: (-x["total_upvotes"], -x["total_emojis"], x["product_id"]),
    )


def run_script(path):
    result = subprocess.run(
        [sys.executable, path], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def check_features(expected):
    path = os.path.join(HOME, "features.jsonl")
    assert os.path.isfile(path), f"Output file {path} is missing."
    with open(path, "r", encoding="utf-8") as f:
        actual = [json.loads(line) for line in f if line.strip()]

    assert len(actual) == len(expected), "features.jsonl has an incorrect number of rows."
    for index, (got, want) in enumerate(zip(actual, expected), 1):
        assert set(got) == set(want), f"Feature row {index} has incorrect fields."
        assert got == want, f"Feature row {index} is incorrect: expected {want}, got {got}."
        assert type(got["upvotes"]) is int
        assert type(got["char_count"]) is int
        assert type(got["emoji_count"]) is int
        assert type(got["has_latin"]) is bool


def read_metric_csv(path):
    assert os.path.isfile(path), f"Output file {path} is missing."
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)
    assert rows, f"Output file {path} is empty."
    assert rows[0] == HEADERS, f"Headers in {path} do not match. Expected {HEADERS}, got {rows[0]}."
    return rows


def check_metric_rows(path, expected, ordered):
    rows = read_metric_csv(path)
    assert len(rows) >= len(expected) + 1, (
        f"Expected at least {len(expected) + 1} rows in {path} (including header), found {len(rows)}."
    )
    assert len(rows) == len(expected) + 1, f"Unexpected extra rows in {path}."

    actual = rows[1:]
    if not ordered:
        actual = sorted(actual, key=lambda row: row[0])
        expected = sorted(expected, key=lambda row: row["product_id"])

    for i, (actual_row, want) in enumerate(zip(actual, expected), 1):
        assert actual_row[0] == want["product_id"], (
            f"Row {i} product_id mismatch. Expected {want['product_id']}, got {actual_row[0]}."
        )
        assert int(actual_row[1]) == want["total_upvotes"], (
            f"Row {i} total_upvotes mismatch. Expected {want['total_upvotes']}, got {actual_row[1]}."
        )
        assert int(actual_row[2]) == want["total_emojis"], (
            f"Row {i} total_emojis mismatch. Expected {want['total_emojis']}, got {actual_row[2]}."
        )
        assert actual_row[3] == want["avg_char_count"], (
            f"Row {i} avg_char_count mismatch. Expected {want['avg_char_count']}, got {actual_row[3]}."
        )


def remove_outputs():
    for path in OUTPUTS:
        if os.path.exists(path):
            os.remove(path)


def test_scripts_exist():
    for script in SCRIPTS:
        assert os.path.isfile(script), f"Required script {script} is missing."


def test_pipeline_and_stages_are_correct():
    with open(RAW, "rb") as f:
        original_raw = f.read()

    try:
        # Execute the master pipeline on the supplied data and derive all expected
        # values from that input using Python character counts.
        original_rows = read_raw()
        original_features = expected_features(original_rows)
        original_aggregates = expected_aggregates(original_features)
        original_sorted = sorted_aggregates(original_aggregates)

        remove_outputs()
        run_script(os.path.join(HOME, "pipeline.py"))
        check_features(original_features)
        check_metric_rows(os.path.join(HOME, "aggregated.csv"), original_aggregates, False)
        check_metric_rows(os.path.join(HOME, "final_metrics.csv"), original_sorted, True)

        # Exercise each stage on a second input so precomputed final output cannot pass.
        challenge = [
            ["review_id", "product_id", "text", "upvotes"],
            ["x1", "ZETA", "A😀", "2"],
            ["x2", "ALPHA", "漢字", "4"],
            ["x3", "ZETA", "é!", "3"],
            ["x4", "BETA", "abc 👍👍", "5"],
            ["x5", "ALPHA", "Q", "1"],
        ]
        with open(RAW, "w", encoding="utf-8", newline="") as f:
            csv.writer(f).writerows(challenge)

        challenge_rows = read_raw()
        challenge_features = expected_features(challenge_rows)
        challenge_aggregates = expected_aggregates(challenge_features)
        challenge_sorted = sorted_aggregates(challenge_aggregates)

        remove_outputs()
        run_script(os.path.join(HOME, "extract.py"))
        check_features(challenge_features)
        run_script(os.path.join(HOME, "aggregate.py"))
        check_metric_rows(os.path.join(HOME, "aggregated.csv"), challenge_aggregates, False)
        run_script(os.path.join(HOME, "sort.py"))
        check_metric_rows(os.path.join(HOME, "final_metrics.csv"), challenge_sorted, True)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
