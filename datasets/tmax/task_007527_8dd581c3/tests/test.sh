#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import secrets
import subprocess
import pytest

PROJECT_DIR = "/home/user/etl_pipeline"
INPUT_CSV = os.path.join(PROJECT_DIR, "input.csv")
OUTPUT_CSV = os.path.join(PROJECT_DIR, "output.csv")


def test_output_csv_exists():
    output_csv_path = "/home/user/etl_pipeline/output.csv"
    assert os.path.isfile(output_csv_path), f"Expected output file {output_csv_path} does not exist. Did the Rust program run successfully?"


def test_output_csv_content():
    output_csv_path = "/home/user/etl_pipeline/output.csv"
    assert os.path.isfile(output_csv_path), "Output file missing."

    expected_rows = [
        ['id', 'email', 'score', 'comments'],
        ['1', '***@example.com', '85', 'Great service,\nwill use again.'],
        ['4', '***@domain.net', '92', 'Normal comment'],
        ['6', '***@corp.com', '0', 'Zero is valid,\nand it has\nmultiple newlines'],
        ['7', '***', '100', 'Missing at sign']
    ]

    actual_rows = []
    with open(output_csv_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, but got {actual}."


def test_rust_source_modified():
    main_rs_path = "/home/user/etl_pipeline/src/main.rs"
    assert os.path.isfile(main_rs_path), "main.rs is missing."
    with open(main_rs_path, 'r', encoding='utf-8') as f:
        content = f.read()
    assert "csv" in content or "Reader" in content or "Writer" in content, "main.rs does not seem to use the csv crate."
    assert "Hello, world!" not in content or len(content) > 50, "main.rs appears to be unmodified."


def derive_expected(rows):
    expected = [["id", "email", "score", "comments"]]
    for row in rows:
        try:
            score = int(row[2])
        except ValueError:
            continue
        if score < 0:
            continue

        email = row[1]
        if "@" in email:
            masked_email = "***@" + email.split("@", 1)[1]
        else:
            masked_email = "***"
        expected.append([row[0], masked_email, row[2], row[3]])
    return expected


def test_pipeline_executes_on_fresh_inputs():
    original_input = open(INPUT_CSV, "rb").read()
    original_output = open(OUTPUT_CSV, "rb").read() if os.path.isfile(OUTPUT_CSV) else None

    try:
        for iteration in range(2):
            token = secrets.token_hex(8)
            rows = [
                [f"valid-{token}", f"person.{token}@example-{token}.com", "37", f"fresh {token}, value\nsecond line"],
                [f"negative-{token}", f"bad@negative-{token}.net", "-1", "must be dropped"],
                [f"missing-{token}", f"missing@score-{token}.org", "", "missing score"],
                [f"invalid-{token}", f"invalid@score-{token}.org", f"not-{token}", "invalid score"],
                [f"zero-{token}", f"no-at-{token}", "0", f"zero, quoted \"comment\" {iteration}"],
                [f"valid2-{token}", f"another_{token}@warehouse-{token}.io", "9", "plain valid row"],
                [f"empty-domain-{token}", f"local-{token}@", "4", "email with empty domain"],
            ]

            with open(INPUT_CSV, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(["id", "email", "score", "comments"])
                writer.writerows(rows)

            if os.path.exists(OUTPUT_CSV):
                os.remove(OUTPUT_CSV)

            result = subprocess.run(
                ["cargo", "run", "--quiet"],
                cwd=PROJECT_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
            assert result.returncode == 0, (
                "The Rust ETL program failed on a fresh input.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(OUTPUT_CSV), "Running the Rust program did not create output.csv."

            with open(OUTPUT_CSV, "r", newline="", encoding="utf-8") as f:
                actual = list(csv.reader(f))

            expected = derive_expected(rows)
            assert actual == expected, (
                "Pipeline output was incorrect for a freshly generated input. "
                f"Expected {expected!r}, got {actual!r}."
            )
    finally:
        with open(INPUT_CSV, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT_CSV):
                os.remove(OUTPUT_CSV)
        else:
            with open(OUTPUT_CSV, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
