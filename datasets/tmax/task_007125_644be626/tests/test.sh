#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess

import pytest


def test_output_json_exists():
    file_path = "/home/user/output.json"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. Did the script run successfully?"


def test_output_json_content():
    file_path = "/home/user/output.json"

    with open(file_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected_data = [
        {
            "ID": "1",
            "Name": "Alice",
            "Email": "alice@example.com",
            "Comments": "Good customer"
        },
        {
            "ID": "3",
            "Name": "Charlie",
            "Email": "charlie@example.com",
            "Comments": "Standard tier"
        },
        {
            "ID": "5",
            "Name": "Dave",
            "Email": "dave@example.com",
            "Comments": "Normal row"
        },
        {
            "ID": "7",
            "Name": "Frank",
            "Email": "frank@example.com",
            "Comments": "Another good customer"
        }
    ]

    assert isinstance(data, list), "Output JSON must be an array of objects."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} rows in output, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f"Row {i} in output JSON does not match expected data.\nExpected: {expected}\nActual: {actual}"


def _derive_expected(csv_path):
    expected = []
    seen = set()
    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["ID", "Name", "Email", "Comments"]
        for row in reader:
            assert None not in row and all(value is not None for value in row.values())
            if any("\n" in value or "\r" in value for value in row.values()):
                continue
            digest = hashlib.md5(row["Email"].lower().encode("utf-8")).digest()
            if digest in seen:
                continue
            seen.add(digest)
            expected.append({header: row[header] for header in reader.fieldnames})
    return expected


def test_process_go_compiles_and_handles_unseen_csv():
    source = Path("/home/user/process.go")
    input_path = Path("/home/user/input.csv")
    output_path = Path("/home/user/output.json")
    binary = Path("/tmp/process_submission")

    assert source.is_file(), "/home/user/process.go is missing or is not a file."

    build = subprocess.run(
        ["go", "build", "-o", str(binary), str(source)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"process.go did not compile:\n{build.stderr}"

    original_input = input_path.read_bytes() if input_path.exists() else None
    original_output = output_path.read_bytes() if output_path.exists() else None
    token = secrets.token_hex(10)
    first_email = f"first-{token}@example.test"
    rejected_email = f"rejected-{token}@example.test"

    rows = [
        [f"id-{token}-1", "Quoted, Name", first_email, 'Contains a "quote", but no newline'],
        [f"id-{token}-2", "Embedded LF", f"lf-{token}@example.test", "line one\nline two"],
        [f"id-{token}-3", "Case Duplicate", first_email.upper(), "must be removed"],
        [f"id-{token}-4", "Embedded CR", f"cr-{token}@example.test", "left\rright"],
        [f"id-{token}-5", "Rejected First", rejected_email, "bad\ncomment"],
        [f"id-{token}-6", "Valid After Rejected", rejected_email.upper(), "must survive"],
        [f"id-{token}-7", "Unicode User", f"unique-{token}@example.test", "café customer"],
        [f"id-{token}-8", "Second Duplicate", f"UNIQUE-{token}@EXAMPLE.TEST", "must be removed"],
        [f"id-{token}-9", "Empty Fields", f"empty-{token}@example.test", ""],
    ]

    try:
        with open(input_path, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["ID", "Name", "Email", "Comments"])
            writer.writerows(rows)

        expected = _derive_expected(input_path)
        if output_path.exists() or output_path.is_symlink():
            output_path.unlink()

        run = subprocess.run(
            [str(binary)],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run.returncode == 0, f"Compiled process failed:\n{run.stderr}"
        assert output_path.is_file(), "Running the compiled process did not create output.json."

        try:
            with open(output_path, "r", encoding="utf-8") as f:
                actual = json.load(f)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            pytest.fail(f"Generated output.json is not valid UTF-8 JSON: {exc}")

        assert isinstance(actual, list), "Generated output JSON must be an array."
        assert actual == expected, f"Unexpected output for unseen CSV input.\nExpected: {expected}\nActual: {actual}"
        for record in actual:
            assert isinstance(record, dict)
            assert set(record.keys()) == {"ID", "Name", "Email", "Comments"}
            assert all(isinstance(value, str) for value in record.values())
    finally:
        if original_input is None:
            if input_path.exists() or input_path.is_symlink():
                input_path.unlink()
        else:
            if input_path.is_symlink():
                input_path.unlink()
            input_path.write_bytes(original_input)

        if original_output is None:
            if output_path.exists() or output_path.is_symlink():
                output_path.unlink()
        else:
            if output_path.is_symlink():
                output_path.unlink()
            output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
