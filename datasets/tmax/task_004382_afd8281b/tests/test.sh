#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
from pathlib import Path
import re
import secrets
import subprocess

import pytest

PROJECT = Path("/home/user/etl_pipeline")
RAW_FILE = Path("/home/user/raw/data.csv")
OUTPUT_FILE = Path("/home/user/processed/output.jsonl")

ORIGINAL_CSV = '''id,name,email,dob,ssn,notes
1,Alice Smith, ALICE@example.com ,1990-01-01,123-45-6789,Regular user
2,Bob Jones,bob@example.com,1985-05-15,987-65-4321,"This is a multiline
note for Bob.
It has newlines."
1,Alice Smith,alice@example.com,1990-01-01,123-45-6789,Duplicate ID should be dropped
3,Charlie Brown,charlie.example.com,1992-11-20,111-22-3333,Invalid email without at symbol
4,David Lee,david@example.com,10-10-2000,222-33-4444,Invalid DOB format
5,Eve Davis,eve@example.com,1995-12-31,333-44-5555,Valid user record
'''


def run_pipeline():
    if OUTPUT_FILE.exists():
        OUTPUT_FILE.unlink()
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The Rust ETL program failed when executed with cargo run.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT_FILE.is_file(), "The executed ETL pipeline did not generate output.jsonl."


def read_output():
    records = []
    try:
        with OUTPUT_FILE.open("r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    records.append(json.loads(line.strip()))
    except Exception as e:
        pytest.fail(f"Error reading JSONL file: {e}. Ensure the file contains valid JSON per line.")
    return records


@pytest.fixture(scope="session", autouse=True)
def execute_rust_project():
    assert PROJECT.is_dir(), "Error: /home/user/etl_pipeline does not exist."
    assert (PROJECT / "Cargo.toml").is_file(), "The ETL pipeline must be a Cargo project with Cargo.toml."
    assert (PROJECT / "src" / "main.rs").is_file(), "The Cargo project must contain a Rust src/main.rs program."
    RAW_FILE.parent.mkdir(parents=True, exist_ok=True)
    RAW_FILE.write_text(ORIGINAL_CSV, encoding="utf-8")
    run_pipeline()


def test_output_file_exists():
    output_file = "/home/user/processed/output.jsonl"
    assert os.path.exists(output_file), f"Error: {output_file} does not exist. The ETL pipeline must generate this file."


def test_output_file_content():
    output_file = "/home/user/processed/output.jsonl"
    assert os.path.exists(output_file), f"Error: {output_file} does not exist."

    expected_records = [
        {
            "id": "1",
            "name": "Alice Smith",
            "email": "alice@example.com",
            "dob": "1990-01-01",
            "ssn": "***-**-6789",
            "notes": "Regular user"
        },
        {
            "id": "2",
            "name": "Bob Jones",
            "email": "bob@example.com",
            "dob": "1985-05-15",
            "ssn": "***-**-4321",
            "notes": "This is a multiline\nnote for Bob.\nIt has newlines."
        },
        {
            "id": "5",
            "name": "Eve Davis",
            "email": "eve@example.com",
            "dob": "1995-12-31",
            "ssn": "***-**-5555",
            "notes": "Valid user record"
        }
    ]

    actual_records = read_output()
    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} valid records, but found {len(actual_records)}. Check your deduplication and validation logic."

    for i, (expected, actual) in enumerate(zip(expected_records, actual_records)):
        assert expected == actual, f"Record at index {i} does not match expected output.\nExpected: {expected}\nActual: {actual}"


def test_pipeline_on_generated_csv():
    token = secrets.token_hex(6)
    rows = [
        [f"a-{token}", "Generated Alice", f"  {token.upper()}@Example.COM  ", "2001-02-03", "101-20-3001", "first generated record"],
        [f"b-{token}", "Generated Bob", f"bob-{token}@example.net", "1988-12-09", "202-30-4002", f"line one {token}\nline two, with comma\nline three with \"quotes\""],
        [f"a-{token}", "Duplicate Alice", f"duplicate-{token}@example.com", "1999-01-01", "303-40-5003", "duplicate must be dropped"],
        [f"c-{token}", "Bad Email", f"invalid-{token}.example.com", "1990-03-04", "404-50-6004", "invalid email"],
        [f"d-{token}", "Bad DOB", f"dob-{token}@example.com", "04-05-1991", "505-60-7005", "invalid dob"],
        [f"e-{token}", "First Invalid", f"first-{token}.example.com", "1992-06-07", "606-70-8006", "first duplicate is invalid"],
        [f"e-{token}", "Later Valid", f"later-{token}@example.com", "1992-06-07", "707-80-9007", "later duplicate remains dropped"],
        [f"f-{token}", "Generated Eve", f"eve-{token}@example.org", "1977-10-11", "808-90-1234", f"final note {token}"],
    ]

    with RAW_FILE.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "name", "email", "dob", "ssn", "notes"])
        writer.writerows(rows)

    expected = []
    seen = set()
    for row in rows:
        record_id, name, email, dob, ssn, notes = row
        if record_id in seen:
            continue
        seen.add(record_id)
        email = email.strip().lower()
        if "@" not in email:
            continue
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", dob) is None:
            continue
        expected.append({
            "id": record_id,
            "name": name,
            "email": email,
            "dob": dob,
            "ssn": "***-**-" + ssn[-4:],
            "notes": notes,
        })

    run_pipeline()
    actual = read_output()
    assert actual == expected, f"Pipeline output for generated CSV was incorrect.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
