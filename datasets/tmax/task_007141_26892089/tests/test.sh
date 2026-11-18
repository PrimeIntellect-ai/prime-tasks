#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess

PROJECT = "/home/user/nlp_prep"
SOURCE = os.path.join(PROJECT, "src/main.rs")
DATASET = "/home/user/dataset.csv"
TOP_CSV = "/home/user/top_tokens.csv"
METRICS_JSON = "/home/user/experiment_metrics.json"

ORIGINAL_DATASET = """id,text
1,The quick brown fox
2,Jumps over the lazy dog
3,The dog barks
"""


def write_dataset(rows):
    with open(DATASET, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "text"])
        writer.writerows(rows)


def run_project():
    for path in (TOP_CSV, METRICS_JSON):
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run(
        ["cargo", "run", "--release"],
        cwd=PROJECT,
        check=True,
        timeout=180,
    )


def read_and_check(expected_counts, preserve_original_assertions=False):
    total_tokens = sum(expected_counts.values())
    vocab_size = len(expected_counts)
    denominator = total_tokens + vocab_size
    expected_top = sorted(expected_counts.items(), key=lambda item: (-item[1], item[0]))[:3]
    expected_rows = [
        [token, f"{(count + 1) / denominator:.6f}"]
        for token, count in expected_top
    ]

    assert os.path.isfile(METRICS_JSON), f"File {METRICS_JSON} does not exist. Did you run the Rust program?"
    with open(METRICS_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            raise AssertionError(f"{METRICS_JSON} does not contain valid JSON.")

    assert "vocab_size" in data, f"'vocab_size' key missing in {METRICS_JSON}."
    assert "total_tokens" in data, f"'total_tokens' key missing in {METRICS_JSON}."
    assert data["vocab_size"] == vocab_size, f"Expected vocab_size to be {vocab_size}, got {data['vocab_size']}."
    assert data["total_tokens"] == total_tokens, f"Expected total_tokens to be {total_tokens}, got {data['total_tokens']}."

    assert os.path.isfile(TOP_CSV), f"File {TOP_CSV} does not exist. Did you run the Rust program?"
    with open(TOP_CSV, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, f"{TOP_CSV} is empty."
    header = rows[0]
    assert header == ["token", "probability"], f"Expected header ['token', 'probability'], got {header}."
    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected exactly 3 data rows in {TOP_CSV}, got {len(data_rows)}."

    if preserve_original_assertions:
        original_expected = [
            ["the", "0.190476"],
            ["dog", "0.142857"],
            ["barks", "0.095238"],
        ]
        assert expected_rows == original_expected

    for i, (expected, actual) in enumerate(zip(expected_rows, data_rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."


def mixed_case(token, occurrence):
    if occurrence % 3 == 0:
        return token.upper()
    if occurrence % 3 == 1:
        return token.capitalize()
    return token


def main():
    assert os.path.exists(SOURCE), f"Required Rust source {SOURCE} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"{SOURCE} must be a regular source file."

    try:
        # Preserve and execute the original fixed-dataset checks.
        with open(DATASET, "w") as f:
            f.write(ORIGINAL_DATASET)
        run_project()
        read_and_check(
            {
                "the": 3,
                "quick": 1,
                "brown": 1,
                "fox": 1,
                "jumps": 1,
                "over": 1,
                "lazy": 1,
                "dog": 2,
                "barks": 1,
            },
            preserve_original_assertions=True,
        )

        # Exercise the compiled project on an unpredictable dataset so fixed
        # prewritten output files cannot satisfy the verifier.
        prefix = "q" + secrets.token_hex(8)
        expected_counts = {
            prefix + "alpha": 6,
            prefix + "beta": 4,
            prefix + "gamma": 4,
            prefix + "delta": 2,
            prefix + "epsilon": 1,
            prefix + "zeta": 1,
        }

        words = []
        for token, count in expected_counts.items():
            for occurrence in range(count):
                words.append(mixed_case(token, occurrence))
        secrets.SystemRandom().shuffle(words)

        rows = []
        index = 0
        row_id = 1
        while index < len(words):
            width = min(3 + (row_id % 3), len(words) - index)
            rows.append([row_id, " ".join(words[index:index + width])])
            index += width
            row_id += 1

        write_dataset(rows)
        run_project()
        read_and_check(expected_counts)

        # Leave the requested outputs corresponding to the task's original dataset.
        with open(DATASET, "w") as f:
            f.write(ORIGINAL_DATASET)
        run_project()
        read_and_check(
            {
                "the": 3,
                "quick": 1,
                "brown": 1,
                "fox": 1,
                "jumps": 1,
                "over": 1,
                "lazy": 1,
                "dog": 2,
                "barks": 1,
            },
            preserve_original_assertions=True,
        )
    finally:
        with open(DATASET, "w") as f:
            f.write(ORIGINAL_DATASET)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
