#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import stat
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

EVIL_DIR = "/app/corpora/evil"
CLEAN_DIR = "/app/corpora/clean"
SCRIPT_PATH = "/home/user/sanitize.py"
PACKAGE_DIR = "/app/vendored/pii-masker"

SSN_REGEX = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
EMAIL_REGEX = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def deduplicate_csv(input_path):
    seen_users = set()
    rows = []
    with open(input_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            user_id = row.get("user_id")
            if user_id not in seen_users:
                seen_users.add(user_id)
                rows.append(row)
    return rows


def expected_rows(input_path, sanitize):
    rows = deduplicate_csv(input_path)
    result = []
    for row in rows:
        copied = dict(row)
        if sanitize:
            copied["feedback"] = EMAIL_REGEX.sub(
                "[EMAIL]", SSN_REGEX.sub("[SSN]", copied["feedback"])
            )
        result.append(copied)
    return result


def run_sanitizer(input_path, output_path, env=None):
    return subprocess.run(
        [sys.executable, SCRIPT_PATH, str(input_path), str(output_path)],
        capture_output=True,
        text=True,
        timeout=15,
        env=env,
    )


def read_output(path):
    assert os.path.isfile(path), "Sanitizer did not create its output CSV"
    with open(path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["user_id", "date", "feedback"], (
            f"Wrong output column order: {reader.fieldnames}"
        )
        rows = list(reader)
    assert all(None not in row for row in rows), "Output contains extra columns"
    return rows


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Sanitize script not found at {SCRIPT_PATH}"
    mode = os.stat(SCRIPT_PATH).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), (
        "sanitize.py is not executable"
    )


def test_vendored_package_installs_and_masks_correctly():
    install = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", PACKAGE_DIR],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert install.returncode == 0, install.stdout + install.stderr

    check_code = r'''
from pathlib import Path
import pii_masker
from pii_masker import mask_text
assert str(Path(pii_masker.__file__).resolve()).startswith("/app/vendored/pii-masker/")
source = "SSN 321-54-9876; mail First.Last+tag@example.co.uk"
assert mask_text(source) == "SSN [SSN]; mail [EMAIL]"
clean = "Serial 123-45-67890 and Twitter @company"
assert mask_text(clean) == clean
'''
    checked = subprocess.run(
        [sys.executable, "-c", check_code],
        capture_output=True,
        text=True,
        timeout=15,
        cwd="/tmp",
    )
    assert checked.returncode == 0, checked.stdout + checked.stderr


def test_evil_corpus_sanitized():
    evil_files = sorted(f for f in os.listdir(EVIL_DIR) if f.endswith(".csv"))
    assert evil_files, "No CSV files found in evil corpus."

    for filename in evil_files:
        input_path = os.path.join(EVIL_DIR, filename)
        with tempfile.TemporaryDirectory() as td:
            output_path = os.path.join(td, "result.csv")
            result = run_sanitizer(input_path, output_path)
            assert result.returncode == 0, result.stdout + result.stderr

            expected = expected_rows(input_path, sanitize=True)
            actual = read_output(output_path)
            assert len(actual) == len(deduplicate_csv(input_path)), (
                f"Deduplication failed for {filename}"
            )
            assert actual == expected, f"Incorrect sanitized output for {filename}"
            for row in actual:
                assert not SSN_REGEX.search(row["feedback"]), filename
                assert not EMAIL_REGEX.search(row["feedback"]), filename


def test_clean_corpus_preserved():
    clean_files = sorted(f for f in os.listdir(CLEAN_DIR) if f.endswith(".csv"))
    assert clean_files, "No CSV files found in clean corpus."

    for filename in clean_files:
        input_path = os.path.join(CLEAN_DIR, filename)
        with tempfile.TemporaryDirectory() as td:
            output_path = os.path.join(td, "result.csv")
            result = run_sanitizer(input_path, output_path)
            assert result.returncode == 0, result.stdout + result.stderr

            expected = expected_rows(input_path, sanitize=False)
            actual = read_output(output_path)
            assert len(actual) == len(deduplicate_csv(input_path)), (
                f"Deduplication failed for {filename}"
            )
            assert actual == expected, f"Clean data was modified for {filename}"


def test_randomized_unseen_csv_is_processed_exactly():
    token = uuid.uuid4().hex
    email = f"person.{token[:10]}+tag@example.org"
    ssn = f"{int(token[:3], 16) % 900 + 100:03d}-{int(token[3:5], 16) % 90 + 10:02d}-{int(token[5:9], 16) % 9000 + 1000:04d}"
    user_a = "u-" + token[:12]
    user_b = "u-" + token[12:24]
    user_c = "u-" + token[20:32]

    rows = [
        [user_a, "2041-02-03", f"Contact {email}, SSN {ssn}"],
        [user_a, "2041-02-04", "duplicate containing another@example.com"],
        [user_b, "2042-05-06", "Serial 123-45-67890 and Twitter @company"],
        [user_c, "2043-07-08", f"Again {ssn}; alternate {email}"],
    ]

    with tempfile.TemporaryDirectory(prefix="sanitize-unseen-") as td:
        input_path = os.path.join(td, token + ".csv")
        output_path = os.path.join(td, uuid.uuid4().hex + ".csv")
        with open(input_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["user_id", "date", "feedback"])
            writer.writerows(rows)

        result = run_sanitizer(input_path, output_path)
        assert result.returncode == 0, result.stdout + result.stderr
        actual = read_output(output_path)
        expected = expected_rows(input_path, sanitize=True)
        assert actual == expected
        assert actual[1]["feedback"] == "Serial 123-45-67890 and Twitter @company"
        assert "[SSN]" in actual[0]["feedback"]
        assert "[EMAIL]" in actual[0]["feedback"]


def test_sanitizer_uses_pii_masker_library():
    token = "LIBRARY_USED_" + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="masker-shadow-") as td:
        package = Path(td) / "pii_masker"
        package.mkdir()
        implementation = f"def mask_text(text):\n    return {token!r} + ':' + text\n"
        (package / "masker.py").write_text(implementation, encoding="utf-8")
        (package / "__init__.py").write_text(
            "from .masker import mask_text\n", encoding="utf-8"
        )

        input_path = Path(td) / "input.csv"
        output_path = Path(td) / "output.csv"
        original = "ordinary feedback " + uuid.uuid4().hex
        with input_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["user_id", "date", "feedback"])
            writer.writerow(["shadow-user", "2050-01-01", original])

        env = os.environ.copy()
        env["PYTHONPATH"] = td + os.pathsep + env.get("PYTHONPATH", "")
        result = run_sanitizer(input_path, output_path, env=env)
        assert result.returncode == 0, result.stdout + result.stderr
        actual = read_output(output_path)
        assert actual == [{
            "user_id": "shadow-user",
            "date": "2050-01-01",
            "feedback": token + ":" + original,
        }], "sanitize.py did not use pii_masker.mask_text"


def test_requires_exactly_two_positional_arguments():
    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.csv")
        output_path = os.path.join(td, "output.csv")
        with open(input_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["user_id", "date", "feedback"])
            writer.writerow(["1", "2020-01-01", "hello"])

        invocations = [
            [sys.executable, SCRIPT_PATH],
            [sys.executable, SCRIPT_PATH, input_path],
            [sys.executable, SCRIPT_PATH, input_path, output_path, "extra"],
        ]
        for command in invocations:
            result = subprocess.run(
                command, capture_output=True, text=True, timeout=15
            )
            assert result.returncode != 0, (
                f"Unexpectedly accepted argument list: {command[2:]}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
