#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import secrets
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
import pytest


def test_files_exist():
    """Verify that the required files have been created."""
    required_files = [
        "/home/user/parser.cpp",
        "/home/user/parser",
        "/home/user/setup_cron.sh",
        "/home/user/processed_locales.jsonl"
    ]
    for file_path in required_files:
        assert os.path.exists(file_path), f"Required file {file_path} is missing."
        assert os.path.isfile(file_path), f"{file_path} is not a regular file."


def test_executable():
    """Verify that the compiled parser is executable and is a native binary."""
    assert os.access("/home/user/parser", os.X_OK), "/home/user/parser is not executable."
    with open("/home/user/parser", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/parser is not a compiled ELF executable."


def test_jsonl_output():
    """Verify the content of the processed JSONL file."""
    output_path = "/home/user/processed_locales.jsonl"

    expected_data = [
        {"id": "1", "timestamp": "2023-10-05T14:30:00Z", "lang": "es", "text": "Hola,\nmundo"},
        {"id": "2", "timestamp": "2023-10-06T09:15:00Z", "lang": "fr", "text": "Bonjour le monde"},
        {"id": "3", "timestamp": "2023-10-07T11:00:22Z", "lang": "de", "text": "Das ist ein \"Test\"\nmit\nneuen Zeilen"}
    ]

    with open(output_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_data), f"Expected {len(expected_data)} lines in JSONL, found {len(lines)}."

    for i, (line, expected) in enumerate(zip(lines, expected_data)):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

        assert parsed == expected, f"Line {i+1} JSON content does not match expected.\nFound: {parsed}\nExpected: {expected}"


def test_cronjob_configured():
    """Verify that the cronjob was correctly installed."""
    try:
        result = subprocess.run(
            ["crontab", "-l"],
            capture_output=True,
            text=True,
            check=True
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run 'crontab -l'. The cronjob might not be set up.")

    expected_cron = "30 2 * * * /home/user/parser /home/user/locales.csv /home/user/processed_locales.jsonl"

    found = False
    for line in crontab_output.splitlines():
        # Remove extra whitespace to make the check robust
        normalized_line = " ".join(line.strip().split())
        normalized_expected = " ".join(expected_cron.split())
        if normalized_expected in normalized_line:
            found = True
            break

    assert found, f"Expected cronjob not found in crontab. Expected to find:\n{expected_cron}"


def _make_random_fixture(path):
    token = secrets.token_hex(12)
    base = datetime(2024, 1, 1, tzinfo=timezone.utc) + timedelta(
        days=secrets.randbelow(700),
        seconds=secrets.randbelow(24 * 60 * 60),
    )
    rows = []
    texts = [
        f"Random {token}, with comma\nsecond line with \"inner quotes\"\nthird line",
        f"Single line, comma, and token {token[::-1]}",
        f"First {token}\n\nline after an empty embedded line",
    ]
    langs = ["es", "fr", "de"]
    for index, text in enumerate(texts):
        stamp = base + timedelta(days=index, seconds=index * 137)
        rows.append({
            "id": str(10000 + secrets.randbelow(80000) + index),
            "timestamp": stamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "input_timestamp": stamp.strftime("%Y/%m/%d-%H:%M:%S"),
            "lang": langs[index],
            "text": text,
        })

    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("id,timestamp,lang,text\n")
        for row in rows:
            quoted_text = '"' + row["text"].replace('"', '""') + '"'
            f.write(f'{row["id"]},{row["input_timestamp"]},{row["lang"]},{quoted_text}\n')

    return [
        {"id": row["id"], "timestamp": row["timestamp"], "lang": row["lang"], "text": row["text"]}
        for row in rows
    ]


def _exercise_parser(executable):
    with tempfile.TemporaryDirectory(prefix="parser-verification-") as tmpdir:
        input_path = os.path.join(tmpdir, secrets.token_hex(8) + ".csv")
        output_path = os.path.join(tmpdir, secrets.token_hex(8) + ".jsonl")
        expected = _make_random_fixture(input_path)

        result = subprocess.run(
            [executable, input_path, output_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Parser {executable} exited with {result.returncode}. "
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(output_path), "Parser did not create the requested output file."

        with open(output_path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
        assert len(lines) == len(expected), (
            f"Expected {len(expected)} physical JSONL lines, found {len(lines)}."
        )

        parsed = []
        for index, line in enumerate(lines, 1):
            assert line.strip(), f"Output line {index} is empty."
            try:
                parsed.append(json.loads(line))
            except json.JSONDecodeError as exc:
                pytest.fail(f"Output line {index} is not valid JSON: {exc}")
        assert parsed == expected, f"Parser output mismatch.\nFound: {parsed}\nExpected: {expected}"


def test_parser_and_source_on_unseen_inputs():
    """Compile the submitted source and exercise both it and the required artifact."""
    with tempfile.TemporaryDirectory(prefix="parser-build-") as tmpdir:
        rebuilt_parser = os.path.join(tmpdir, "parser")
        build = subprocess.run(
            ["g++", "/home/user/parser.cpp", "-o", rebuilt_parser],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, (
            f"parser.cpp failed to compile. stdout: {build.stdout}\nstderr: {build.stderr}"
        )
        _exercise_parser(rebuilt_parser)

    _exercise_parser("/home/user/parser")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
